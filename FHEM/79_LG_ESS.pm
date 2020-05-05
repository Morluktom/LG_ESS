########################################################################################################################
#
#		79_LG_ESS.pm
#
#		Establishes a connection to a LG ESS hybrid inverter. 
#		This module can read out status values and control the inverter.
#
#		Written and best viewed with Notepad++ ; Language Markup: Perl
#
#		Author                     : Thomas Mayer 
#		Fhem Forum                 : https://forum.fhem.de/index.php/topic,110884.0.html
#		Fhem Wiki                  : Not yet implemented
#
#		This file is part of fhem.
#
#		Fhem is free software: you can redistribute it and/or modify
#		it under the terms of the GNU General Public License as published by
#		the Free Software Foundation, either version 2 of the License, or
#		(at your option) any later version.
#
#		Fhem is distributed in the hope that it will be useful,
#		but WITHOUT ANY WARRANTY; without even the implied warranty of
#		MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#		GNU General Public License for more details.
#
#		You should have received a copy of the GNU General Public License
#		along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#		fhem.cfg: define <devicename> LG_ESS <IP-Adress> <Password>
#
#		Example 1:
#		define myEss LG_ESS 192.168.0.240 Password
#
########################################################################################################################

package main;
use strict;
use warnings;
use HTTP::Request::Common;
use LWP::UserAgent;
use JSON;
my %LG_ESS_sets;

#-----------------------------------------------------------------------------------------------------------------------
# Initialize module
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_Initialize($)
{
	my ($hash) = @_;

	$hash->{STATE}				= "Init";
	$hash->{DefFn}				= "LG_ESS_Define";
	$hash->{UndefFn}			= "LG_ESS_Undefine";
	$hash->{SetFn} 				= "LG_ESS_Set";
	$hash->{AttrFn}				= "LG_ESS_Attr";

	$hash->{AttrList}			= "DoNotPoll:0,1 " .
								  "PollingIntervall " .
								   $readingFnAttributes;
}

#-----------------------------------------------------------------------------------------------------------------------
# Activate module after module has been used via fhem command "define"
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_Define($$$)
{
	my ($hash, $def)              = @_;
	my ($name, $type, $Ip, $Password) = split("[ \t]+", $def, 4);

	#Fetching password
	if ($Ip eq "GettingPassword")
	{
		return LG_ESS_GettingPassword($hash);
	}

	# Check whether regular expression has correct syntax
	if(!$Ip || !$Password) 
	{
		return "Wrong syntax: define <name> LG_ESS <Ip-Adress> <Password>";
	}

	# Writing log entry
	Log3 $name, 5, $name. " : LG_ESS - Starting to define module";

	# Check whether IPv4 address is valid
	if ($Ip =~ m/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/)
	{
		Log3 $name, 4, $name. " : LG_ESS - IPv4-address is valid                  : " . $Ip;
	}
	else
	{
		return $name .": Error - IPv4 address is not valid \n Please use \"define <devicename> LG_ESS <IPv4-address> <interval/[s]> <GatewayPassword> <PrivatePassword>\" instead";
	}

	# Stop the current timer if one exists errornous 
	RemoveInternalTimer($hash);
	Log3 $name, 4, $name. " : LG_ESS - InternalTimer has been removed.";

	# Writing values to global hash
	$hash->{NAME}							= $name;
	$hash->{STATE}							= "active";
	$hash->{IP}								= $Ip;
	$hash->{Secret}{PASSWORD}				= $Password;
	$hash->{PollingIntervall}				= 30;
	$hash->{POLLINGTIMEOUT}					= 10;
	$hash->{temp}{LogInRole}				= "User";
	$hash->{Version}						= "1.00.1";

	# Initiate the timer for first time polling of  values from LG_ESS but wait 10s
	InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1);
	Log3 $name, 4, $name. " : LG_ESS - Internal timer for Initialisation of services started for the first time.";

	return undef;
}

#-----------------------------------------------------------------------------------------------------------------------
# Deactivate module module after "undefine" command by fhem
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_Undefine($$)
{
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	

	Log3 $name, 3, $name. " LG_ESS has been undefined.";

	return undef;
}

#-----------------------------------------------------------------------------------------------------------------------
# Handle attributes after changes via fhem GUI
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_Attr(@)
{
	my @a                      = @_;
	my $name                   = $a[1];
	my $hash                   = $defs{$name};
	my $PollingIntervall       = $hash->{PollingIntervall};
	
	# Check whether "DoNotPoll" attribute has been provided
	if ($a[2] eq "DoNotPoll")
	{
		if($a[3] eq 0)
		{	
			# Stop the current timer
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1);
		}
		elsif ($a[3] eq 1)		
		{	
			# Stop the current timer
			RemoveInternalTimer($hash);
		}
	}
	# Check whether dynamic interval attribute has been provided
	elsif ($a[2] eq "PollingIntervall")
	{
		$PollingIntervall = $a[3];
		# Check whether polling interval is not too short
		if ($PollingIntervall > 9)
		{
			$hash->{PollingIntervall} = $PollingIntervall;
			Log3 $name, 4, $name. " : LG_ESS - PollingIntervall set to attribute value:" . $PollingIntervall ." s";
		}
		else
		{
			return $name .": Error - Gateway interval for PollingIntervall too small - server response time longer than defined interval, please use something >=10, default is 30";
		}
	}
	elsif ($a[2] eq "InstallerPassword")
	{
		$hash->{temp}{LogInRole} = "Installer";
		# Stop the current timer
		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1);
	}
	return undef;
}

###START###### Manipulate reading after "set" command by fhem #################################################START####
sub LG_ESS_Set($@)
{
	my ( $hash, $name, $cmd, @args ) = @_;

	return "\"set $name\" needs at least one argument" unless(defined($cmd));

	if($cmd eq "GetState")
	{
		LG_ESS_GetState($hash);
	}
	elsif($cmd eq "BatteryFastChargingMode")
	{
		if($args[0] eq "on")
		{
			LG_ESS_Cmd($hash,"BatteryFastChargingModeOn");
		}
		elsif($args[0] eq "off")
		{
			LG_ESS_Cmd($hash,"BatteryFastChargingModeOff");
		}
		else
		{
			return "Unknown value $args[0] for $cmd, choose one of on/off";  
		}
	}
	elsif($cmd eq "BatteryWinterMode")
	{		
		if($args[0] eq "on")
		{
			LG_ESS_Cmd($hash,"BatteryWinterModeOn");	   
		}
		elsif($args[0] eq "off")
		{
			LG_ESS_Cmd($hash,"BatteryWinterModeOff");
		}
		else
		{
			return "Unknown value $args[0] for $cmd, choose one of on/off";  
		}
	}
	elsif($cmd eq "System")
	{	
		if($args[0] eq "on")
		{
			LG_ESS_Cmd($hash,"EssSwitchOn");	   
		}
		elsif($args[0] eq "off")
		{
			LG_ESS_Cmd($hash,"EssSwitchOff");
		}
		else
		{
			return "Unknown value $args[0] for $cmd, choose one of on/off"; 
		}
	}
#	elsif($cmd eq "InstallerLogin")
#	{
#		$hash->{temp}{LogInRole} = "Installer";
#		LG_ESS_UserLogin($hash);
#	}
#	elsif($cmd eq "Test")
#		LG_ESS_Cmd($hash,"SwitchBatteryOn");
#	}
	else
	{
		return "Unknown argument $cmd, choose one of GetState:noArg System:on,off BatteryFastChargingMode:on,off BatteryWinterMode:on,off";
	}

}

#-----------------------------------------------------------------------------------------------------------------------
# Subroutine for Getting the password
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_GettingPassword($)
{
	my ($hash, $def)				= @_;
	my $name						= $hash->{NAME};
	my $PollingTimeout				= 10;
	
	# Stop the current timer
	RemoveInternalTimer($hash);

	# Set status of fhem module
	$hash->{STATE} = "Getting Password";

	my $url = "https://192.168.23.1/v1/user/setting/read/password";
	my $content = '{"key": "lgepmsuser!@#"}';

	my $sslPara->{sslargs} = { verify_hostname => 0};
	my $param = {
					url			=> $url,
					timeout		=> $PollingTimeout,
					data		=> $content,
					method		=> "POST",
					sslargs		=> $sslPara,
					header		=> "Content-Type: application/json",
				};

	#Function call
	my($err, $data) = HttpUtils_BlockingGet($param);

	my $type;
	my $json ->{type} = "";

	if($err ne "") 
	{
		# Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_GettingPassword - ERROR                : Getting Passwod.: No proper Communication with Gateway: " .$err;
		return "LG ESS: could not fetch password";	
	}
	elsif($data ne "") 
	{

		# Create Log entry for debugging
		Log3 $name, 5, $name . "LG_ESS_GettingPassword Data: ".$data;

		# Decode json
		my $decodedData = decode_json($data);

		if ($decodedData->{'status'} eq "success")
		{
			return "LG ESS Password: ".$decodedData->{'password'};
		}
	}

}

#-----------------------------------------------------------------------------------------------------------------------
# Subroutine initial contact of services via HttpUtils for user login
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_UserLogin($)
{
	my ($hash, $def)				= @_;
	my $ip							= $hash->{IP};
	my $name						= $hash->{NAME};
	my $PollingTimeout				= $hash->{POLLINGTIMEOUT};

	# Stop the current timer
	RemoveInternalTimer($hash);

	# Set status of fhem module
	$hash->{STATE} = "Login";
	my $url;
	my $password;
	
	if ($hash->{temp}{LogInRole} eq "Installer")
	{
		$url = "https://".$ip."/v1/installer/setting/login";
		$password					= AttrVal($name,"InstallerPassword","");
		# Create Log entry for debugging
		Log3 $name, 4, $name . "LG_ESS_UserLogin - Try to log in as installer.";
	}
	else
	{
		$url			= "https://".$ip."/v1/user/setting/login";
		$password	= $hash->{Secret}{PASSWORD};
		# Create Log entry for debugging
		Log3 $name, 4, $name . "LG_ESS_UserLogin - Try to log in as user.";
	}
	my $content = '{"password": "'.$password .'"}';
	
	my $sslPara->{sslargs} = { verify_hostname => 0};
	my $param = {
					url			=> $url,
					timeout		=> $PollingTimeout,
					data		=> $content,
					hash		=> $hash,
					method		=> "PUT",
					sslargs		=> $sslPara,
					header		=> "Content-Type: application/json",
					callback	=> \&LG_ESS_HttpResponseLogin
				};

	#Function call
	HttpUtils_NonblockingGet($param);
}

#-----------------------------------------------------------------------------------------------------------------------
# Subroutine for parsing user login json answer and getting aut_key
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_HttpResponseLogin($)
{
	my ($param, $err, $data)	= @_;
	my $hash					= $param->{hash};
	my $name					= $hash ->{NAME};

	my $type;
	my $json ->{type} = "";

	if($err ne "") 
	{
		# Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_HttpResponseLogin - ERROR                : ".$param->{path}. ": No proper Communication with Gateway: " .$err;

		# Set status of fhem module
		$hash->{STATE} = "ERROR - Initial Connection failed... Try to re-connect in 10s";

		# Start the timer for polling again but wait 10s
		InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1);

		# Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_HttpResponseLogin - ERROR                : Timer restarted to try again in 10s";
		return "ERROR";	
	}
	elsif($data ne "") 
	{
		# Create Log entry for debugging
		Log3 $name, 5, $name . " : LG_ESS_HttpResponseLogin Data:".$data;

		# Decode json
		my $decodedData = decode_json($data);
		my $status = $decodedData->{'status'};
		
		if ($status eq "success")
		{
			$hash->{temp}{AUTH_KEY} = $decodedData->{'auth_key'};
			$hash->{USERROLE} = $decodedData->{'role'};;
			# Create Log entry
			Log3 $name, 3, $name . " : LG_ESS_HttpResponseLogin - Login success!";
			$hash ->{temp}{ServiceCounterInit} = 0;

			LG_ESS_GetState($hash);
		} elsif ($status eq "password_mismatched")
		{
			# Create Log entry
			Log3 $name, 2, $name . " : LG_ESS_HttpResponseLogin - Login failed, password mismatched!  Timer restarted to try again in 10s";

			# Set status of fhem module
			$hash->{STATE} = "ERROR - Login failed... Try to re-connect in 10s";
			if ($hash->{temp}{LogInRole} eq "Installer")
			{
				$hash->{temp}{LogInRole} = "User";
			}
			# Start the timer for polling again but wait 10s
			InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1)
		} else
		{
			# Create Log entry
			Log3 $name, 2, $name . " : LG_ESS_HttpResponseLogin - Login failed!  Timer restarted to try again in 10s";

			# Set status of fhem module
			$hash->{STATE} = "ERROR - Login failed... Try to re-connect in 10s";

			# Start the timer for polling again but wait 10s
			InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1);
		}
	}
}

#-----------------------------------------------------------------------------------------------------------------------
# Subroutine initial contact of services via HttpUtils for getting state values
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_GetState($)
{
	my ($hash, $def)		= @_;
	my $ip					= $hash->{IP};
	my $name				= $hash->{NAME};
	my $PollingIntervall	= $hash->{PollingIntervall};
	my $ServiceCounterInit	= $hash ->{temp}{ServiceCounterInit};
	my $PollingTimeout		= $hash->{POLLINGTIMEOUT};
	my $auth_key			= $hash->{temp}{AUTH_KEY};

	# Writing state urls
	my @state_urls = (
	"/v1/user/setting/network",
	"/v1/user/setting/systeminfo",
	"/v1/user/setting/batt",
	"/v1/user/essinfo/home",
	"/v1/user/essinfo/common",
	);
	my $numberStateUrls = @state_urls;

	# If the list of state_urls has not been finished yet
	if ($ServiceCounterInit >= $numberStateUrls)
	{
		#Reset counter
		$hash ->{temp}{ServiceCounterInit} = 0;

		if (AttrVal($name,"DoNotPoll","") ne "1")
		{
			#Start timer again
			InternalTimer(gettimeofday() + $PollingIntervall, "LG_ESS_GetState", $hash, 1);
			Log3 $name, 4, $name. " : LG_ESS_GetState - Internal timer for Initialisation of services started again.";
		}

		# Set status of fhem module
		$hash->{STATE} = "Standby";
		return;
	}

	my $url = "https://".$ip.$state_urls[$ServiceCounterInit];
	my $sslPara->{sslargs} = { verify_hostname => 0};
	my $content = '{"auth_key": "'.$auth_key .'"}';
	my $param = {
					url			=> $url,
					timeout		=> $PollingTimeout,
					data		=> $content,
					hash		=> $hash,
					method		=> "POST",
					sslargs		=> $sslPara,
					header		=> "Content-Type: application/json",
					callback	=>  \&LG_ESS_HttpResponseState
				};

	# Set status of fhem module
	$hash->{STATE} = "Polling";

	# Function call
	HttpUtils_NonblockingGet($param);
}

#-----------------------------------------------------------------------------------------------------------------------
# Subroutine for parsing state json answer and write in readings
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_HttpResponseState($)
{
	my ($param, $err, $data)	= @_;
	my $hash					= $param->{hash};
	my $name					= $hash ->{NAME};
	my $ServiceCounterInit		= $hash ->{temp}{ServiceCounterInit};

	my $type;
	my $json ->{type} = "";

	if($err ne "") 
	{
		# Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_HttpResponseState - ERROR                : ".$param->{path}. ": No proper Communication with Gateway: " .$err;

		# Set status of fhem module
		$hash->{STATE} = "ERROR - Initial Connection failed... Try to re-connect in 10s";

		# Start the timer for polling again but wait 10s
		InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1);

		# Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_HttpResponseState - ERROR                : Timer restarted to try again in 10s";
		return "ERROR";	
	}
	elsif($data ne "") 
	{

		# Create Log entry for debugging
		Log3 $name, 5, $name . "LG_ESS_HttpResponseState Data: ".$data;

		# Login failed?
		if ($data =~ m/auth_key failed/i)
		{
			# Create Log entry
			Log3 $name, 2, $name . " : LG_ESS_HttpResponseState - Login failed!  Timer restarted to try again in 10s";

			# Set status of fhem module
			$hash->{STATE} = "ERROR - Login failed... Try to re-connect in 10s";

			# Start the timer for polling again but wait 10s
			InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1);
			return "Login failed";
		}

		# Decode json
		my $decodedData = decode_json($data);

		my $record;	
		my $key;
		my $key1;
		my $varName;
		my $value;

		# Initialize Bulkupdate
		readingsBeginUpdate($hash);
		if ($param->{path} eq "/v1/user/essinfo/common")
		{
			foreach $record ($decodedData) {
				foreach $key (keys(%$record)) {
					eval{
						foreach $key1 (keys %{$record->{$key}} ){
							$varName ="/essinfo/common/".$key."/".$key1;
							$value = $record->{$key}{$key1};
							# Write Reading
							readingsBulkUpdate($hash, $varName, $value, 1);
						}
					}
				}
			}
		}
		elsif ($param->{path} eq "/v1/user/essinfo/home")		
		{
			foreach $record ($decodedData) {
				foreach $key (keys(%$record)) {
					eval{
						foreach $key1 (keys %{$record->{$key}} ){
							$varName ="/essinfo/home/".$key."/".$key1;
							$value = $record->{$key}{$key1};
							# Write Reading
							readingsBulkUpdate($hash, $varName, $value, 1);
						}
					}
				}
			}
		}
		elsif ($param->{path} eq "/v1/user/setting/systeminfo")		
		{
			foreach $record ($decodedData) {
				foreach $key (keys(%$record)) {
					eval{
						foreach $key1 (keys %{$record->{$key}} ){
							$varName ="/setting/systeminfo/".$key."/".$key1;
							$value = $record->{$key}{$key1};						
							# Write Reading
							readingsBulkUpdate($hash, $varName, $value, 1);
						}
					}
				}
			}
		}
		elsif ($param->{path} eq "/v1/user/setting/network")
		{
			foreach $record ($decodedData) {
				eval{
					foreach $key (keys %{$record} ){
						$varName ="/setting/network/".$key;
						$value = $record->{$key};
						# Write Reading
						readingsBulkUpdate($hash, $varName, $value, 1);
					}
				}
			}
		}
		elsif ($param->{path} eq "/v1/user/setting/batt")
		{
			foreach $record ($decodedData) {
				eval{
					foreach $key (keys %{$record} ){
						$varName ="/setting/batt/".$key;
						$value = $record->{$key};
						# Write Reading
						readingsBulkUpdate($hash, $varName, $value, 1);
					}
				}
			}
		}
		else
		{
			# Create Log entry
			Log3 $name, 5, $name . " : LG_ESS_HttpResponseState - ".$param->{path}." ".$data;
		}

		# Finish and execute Bulkupdate
		readingsEndUpdate($hash, 1);

		#increase counter
		++$ServiceCounterInit;
		$hash ->{temp}{ServiceCounterInit} = $ServiceCounterInit;
		LG_ESS_GetState($hash);

	}
}

#-----------------------------------------------------------------------------------------------------------------------
# Subroutine for sending a command to ess system
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_Cmd($$)
{
	my ($hash, $cmd)				= @_;
	my $ip							= $hash->{IP};
	my $name						= $hash->{NAME};

	my $PollingTimeout				= $hash->{POLLINGTIMEOUT};
	my $auth_key					= $hash->{temp}{AUTH_KEY};

	# Set status of fhem module
	$hash->{STATE} = $cmd;	

	my $url;
	my $content;
	if ($cmd eq "EssSwitchOn")
	{
		$url = "https://".$ip."/v1/user/operation/status";
		$content = '{"auth_key": "'.$auth_key .'","operation": "start"}';
	}
	elsif ($cmd eq "EssSwitchOff")
	{
		$url = "https://".$ip."/v1/user/operation/status";
		$content = '{"auth_key": "'.$auth_key .'","operation": "stop"}';
	}
	elsif ($cmd eq "BatteryFastChargingModeOn")
	{
		$url = "https://".$ip."/v1/user/setting/batt";
		$content = '{"auth_key": "'.$auth_key .'","alg_setting": "on"}';
	}
	elsif ($cmd eq "BatteryFastChargingModeOff")
	{
		$url = "https://".$ip."/v1/user/setting/batt";
		$content = '{"auth_key": "'.$auth_key .'","alg_setting": "off"}';
	}
	elsif ($cmd eq "BatteryWinterModeOn")
	{
		$url = "https://".$ip."/v1/user/setting/batt";
		$content = '{"auth_key": "'.$auth_key .'","wintermode": "on"}';
	}
	elsif ($cmd eq "BatteryWinterModeOff")
	{
		$url = "https://".$ip."/v1/user/setting/batt";
		$content = '{"auth_key": "'.$auth_key .'","wintermode": "off"}';
	}
	elsif ($cmd eq "SwitchBatteryOff")
	{
		$url = "https://".$ip."/v1/installer/setting/batt";
		$content = '{"auth_key": "'.$auth_key .'","use": "off"}';
	}
	elsif ($cmd eq "SwitchBatteryOn")
	{
		$url = "https://".$ip."/v1/installer/setting/batt";
		$content = '{"auth_key": "'.$auth_key .'","use": "on"}';
	}

	my $sslPara->{sslargs} = { verify_hostname => 0};
	my $param = {
					url			=> $url,
					timeout		=> $PollingTimeout,
					data		=> $content,
					hash		=> $hash,
					method		=> "PUT",
					sslargs		=> $sslPara,
					header		=> { "X-HTTP-Method-Override" => "PUT", "Content-Type" => "application/json" },
					callback	=> \&LG_ESS_HttpResponseCmd
				};

	#Function call
	HttpUtils_NonblockingGet($param);
}

#-----------------------------------------------------------------------------------------------------------------------
# Subroutine for parsing command json answer
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_HttpResponseCmd($)
{
	my ($param, $err, $data)	= @_;
	my $hash					= $param->{hash};
	my $name					= $hash ->{NAME};
	my $PollingIntervall		= $hash->{PollingIntervall};

	my $type;
	my $json ->{type} = "";

	if($err ne "") 
	{
		# Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_HttpResponseCmd - ERROR                : ".$param->{path}. ": No proper Communication with Gateway: " .$err;

		# Set status of fhem module
		$hash->{STATE} = "ERROR - Initial Connection failed... Try to re-connect in 10s";

		# Start the timer for polling again but wait 10s
		InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1);

		# Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_HttpResponseCmd - ERROR                : Timer restarted to try again in 10s";
		return "ERROR";	
	}
	elsif($data ne "") 
	{
		# Create Log entry for debugging
		Log3 $name, 5, $name . "LG_ESS_HttpResponseCmd Data: ".$data;

		# Login failed?
		if ($data =~ m/auth_key failed/i)
		{
			# Create Log entry
			Log3 $name, 2, $name . " : LG_ESS_HttpResponseCmd - Login failed!  Timer restarted to try again in 10s";

			# Set status of fhem module
			$hash->{STATE} = "ERROR - Login failed... Try to re-connect in 10s";

			# Start the timer for polling again but wait 10s
			InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1);
			return "Login failed";
		}

		# Decode json
		my $decodedData = decode_json($data);

		# Create Log entry
		Log3 $name, 5, $name . " : LG_ESS_HttpResponseCmd - ".$$param->{path}." ".$data;

		#Start timer again
		InternalTimer(gettimeofday() + $PollingIntervall, "LG_ESS_GetState", $hash, 1);
		Log3 $name, 4, $name. " : LG_ESS - Internal timer for Initialisation of services started again.";

		# Set status of fhem module
		$hash->{STATE} = "Standby";
	}
}

1;

=pod
=item summary   Module for LG ESS HOME Inverter 
=begin html


	<a name="LG_ESS"></a>

	<h3>LG_ESS</h3>
	<br />
	<div>

	<b>Getting the password</b>
	<div>
	<br />

		To determine the password of the system, this module must be executed using Strawberry Perl on a laptop with WLAN.<br />
		<br />
		<ul>
			<li>Install FHEM on laptop. <a href="https://wiki.fhem.de/wiki/FHEM_Installation_Windows">https://wiki.fhem.de/wiki/FHEM_Installation_Windows</a></li>
			<li>Connect the computer to the LG_ESS system's WLAN. (WiFi password is on the nameplate)</i>
			<li>Enter the following command in the FHEM command line to determine the password: <code> define myESS GettingPassword </code></li>
			<li>Write down the password</li>
		</ul>
	</div><br />

	<b>Define</b>
	<div>
		<br />
		<code>define &lt;name&gt; LG_ESS &lt;ip-address&gt; &lt;password&gt;</code><br />
		<br />
		The module can reads current values and send commands to a LG ESS inverter.<br />
		<br />

		<b>Parameters:</b><br />
		<ul>
			<li><b>&lt;ip-address&gt;</b> - the ip address of the inverter</li>
			<li><b>&lt;password&gt;</b> - the login-password for the inverter</li>
		</ul>

		<b>Example:</b><br />
		<br />
		<div>
			<code>define myEss LG_ESS 192.168.2.4 password</code><br />
		</div>
	</div><br />

	<b>Set-Commands</b>
	<div>
		<br />
		<code>set &lt;name&gt; GetState</code><br />
		<div>
			All values of the inverter are immediately polled.
		</div>
		<br />
		
		<code>set &lt;name&gt; BatteryFastChargingMode &lt;value&gt;</code><br />
		<div>
			"on" switch the system to Fast Charging Mode.<br />
			"off" switch the system to Economic Mode.<br />
		</div><br />
		
		<code>set &lt;name&gt; BatteryWinterMode &lt;value&gt;</code><br />
		<div>
			"on" switch the Winter Mode on.<br />
			"off"switch the Winter Mode off.<br />
		</div><br />		
		<code>set &lt;name&gt; System &lt;value&gt;</code><br />
		<div>
			"on" switch the system on.<br />
			"off" switch the system off.<br />
		</div><br />
	</div>

	<b>Attributes</b><br />

    <ul>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>

      <li><b>PollingIntervall</b> - A valid polling interval for automatic polling. The value must be >=10s. The default value is 30s.</li>
      <li><b>DoNotPoll</b> - with 1 the automatic polling is switched off</li>
    </ul><br />
    <br />
	
  </div>


=end html
=cut