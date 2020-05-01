########################################################################################################################
#
#		99_LG_ESS.pm
#
#		Establishes a connection to a LG ESS hybrid inverter. 
#		This module can read out status values and control the inverter.
#
#		Written and best viewed with Notepad++ ; Language Markup: Perl
#
#		Author                     : Thomas Mayer 
#		Fhem Forum                 : Not yet implemented
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
my %LG_ESS_gets;
my %LG_ESS_sets;

###START###### Initialize module ##############################################################################START####
sub LG_ESS_Initialize($)
{
	my ($hash)  = @_;

	$hash->{STATE}				= "Init";
	$hash->{DefFn}				= "LG_ESS_Define";
	$hash->{UndefFn}			= "LG_ESS_Undefine";
	$hash->{GetFn}				= "LG_ESS_Get";
	$hash->{SetFn} 				= "LG_ESS_Set";
	$hash->{AttrFn}				= "LG_ESS_Attr";

	$hash->{AttrList}       	= "disable:0,1 " .
								  "header " .
								  "IntervalDynVal " .
								   $readingFnAttributes;
}
####END####### Initialize module ###############################################################################END#####

###START###### Activate module after module has been used via fhem command "define" ##########################START####
sub LG_ESS_Define($$$)
{
	my ($hash, $def)              = @_;
	my ($name, $type, $Ip, $Password) = split("[ \t]+", $def, 4);

	#Fetching password
	if ($Ip eq "FetchingPassword")
	{
		return LG_ESS_FetchingPassword($hash);
	}

	### Check whether regular expression has correct syntax
	if(!$Ip || !$Password) 
	{
		my $msg = "Wrong syntax: define <name> LG_ESS <Ip-Adress> <Password>";
		return $msg;
	}

	### Writing log entry
	Log3 $name, 5, $name. " : LG_ESS - Starting to define module";
	
	###START### Check whether IPv4 address is valid
	if ($Ip =~ m/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/)
	{
		Log3 $name, 4, $name. " : LG_ESS - IPv4-address is valid                  : " . $Ip;
	}
	else
	{
		return $name .": Error - IPv4 address is not valid \n Please use \"define <devicename> LG_ESS <IPv4-address> <interval/[s]> <GatewayPassword> <PrivatePassword>\" instead";
	}
	####END#### Check whether IPv4 address is valid	
	
	
	### Stop the current timer if one exists errornous 
	RemoveInternalTimer($hash);
	Log3 $name, 4, $name. " : LG_ESS - InternalTimer has been removed.";
	
	### Writing state urls
	my @STATE_URLS = (
	"/v1/user/setting/network",
	"/v1/user/setting/systeminfo",
	"/v1/user/setting/batt",
	"/v1/user/essinfo/home",
	"/v1/user/essinfo/common",
	);
	
	
	### Writing values to global hash
	$hash->{NAME}							= $name;
	$hash->{STATE}              			= "active";
	$hash->{IP}             				= $Ip;
	$hash->{PASSWORD}          				= $Password;
	$hash->{INTERVALDYNVAL}                 = 30;
	$hash->{POLLINGTIMEOUT}                 = 10;
	@{$hash->{Secret}{STATE_URLS}}          = sort @STATE_URLS;

	###START###### Initiate the timer for first time polling of  values from LG_ESS but wait 10s ###############START####
	InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1);
	Log3 $name, 4, $name. " : LG_ESS - Internal timer for Initialisation of services started for the first time.";
	####END####### Initiate the timer for first time polling of  values from LG_ESS but wait 10s ################END#####


	return undef;
}
####END####### Activate module after module has been used via fhem command "define" ############################END#####

###START###### Deactivate module module after "undefine" command by fhem ######################################START####
sub LG_ESS_Undefine($$)
{
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	

	Log3 $name, 3, $name. " GasTank- The gas calculator has been undefined. Values corresponding to Gas Counter will no longer calculated";
	
	return undef;
}
####END####### Deactivate module module after "undefine" command by fhem #######################################END#####

###START###### Handle attributes after changes via fhem GUI ###################################################START####
sub LG_ESS_Attr(@)
{
	my @a                      = @_;
	my $name                   = $a[1];
	my $hash                   = $defs{$name};
	my $IntervalDynVal         = $hash->{INTERVALDYNVAL};
	
	### Check whether "disable" attribute has been provided
	if ($a[2] eq "disable")
	{
		if    ($a[3] eq 0)
		{	
			$hash->{STATE} = "active";
		}
		elsif ($a[3] eq 1)		
		{	
			$hash->{STATE} = "disabled";
		}
	}
	### Check whether dynamic interval attribute has been provided
	elsif ($a[2] eq "IntervalDynVal")
	{

		$IntervalDynVal = $a[3];
		###START### Check whether polling interval is not too short
		if ($IntervalDynVal > 19)
		{
			$hash->{INTERVALDYNVAL} = $IntervalDynVal;
			Log3 $name, 4, $name. " : km200 - IntervalDynVal set to attribute value:" . $IntervalDynVal ." s";
		}
		else
		{
			return $name .": Error - Gateway interval for IntervalDynVal too small - server response time longer than defined interval, please use something >=20, default is 90";
		}
		####END#### Check whether polling interval is not too short
	}
	return undef;
}
####END####### Handle attributes after changes via fhem GUI ####################################################END#####

###START###### Manipulate reading after "set" command by fhem #################################################START####
sub LG_ESS_Get($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"get SolarUtils\" needs at least one argument";
	}
		
	my $GasCalcName = shift @a;
	my $reading  = shift @a;
	my $value; 
	my $ReturnMessage;

	if(!defined($LG_ESS_gets{$reading})) 
	{
		my @cList = keys %LG_ESS_sets;
		return "Unknown argument $reading, choose one of " . join(" ", @cList);

		### Create Log entries for debugging
		Log3 $GasCalcName, 5, $GasCalcName. " : GasTank - get list: " . join(" ", @cList);
	}
	
	if ( $reading ne "?")
	{
		### Create Log entries for debugging
		Log3 $GasCalcName, 5, $GasCalcName. " : GasTank - get " . $reading . " with value: " . $value;
		
		### Write current value
		$value = ReadingsVal($GasCalcName,  $reading, undef);
		
		### Create ReturnMessage
		$ReturnMessage = $value;
	}
	
	return($ReturnMessage);
}
####END####### Manipulate reading after "set" command by fhem ##################################################END#####

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
	      return "Unknown value $args[0] for $cmd, choose one of GetState SystemOperating BatteryFastChargingMode BatteryWinterMode";  
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
	      return "Unknown value $args[0] for $cmd, choose one of GetState SystemOperating BatteryFastChargingMode BatteryWinterMode";  
	   }  	
	}	
	elsif($cmd eq "SystemOperating")
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
	      return "Unknown value $args[0] for $cmd, choose one of GetState SystemOperating BatteryFastChargingMode"; 
	   }  
	}
	elsif($cmd eq "Test")
	{
		LG_ESS_Cmd($hash,"InstallerLogin");
	}
	else
	{
		return "Unknown argument $cmd, choose one of GetState:noArg SystemOperating:on,off BatteryFastChargingMode:on,off BatteryWinterMode:on,off Test:noArg";
	}

}



#-----------------------------------------------------------------------------------------------------------------------
# Subroutine for fetching the password
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_FetchingPassword($)
{
	my ($hash, $def)				= @_;
	my $name						= $hash->{NAME};
	my $PollingTimeout				= 10;
	$hash->{temp}{SERVICE}			= "Fetching Password";
	my $Service					= $hash->{temp}{SERVICE};
	
	# Stop the current timer
	RemoveInternalTimer($hash);

	# Set status of fhem module
	$hash->{STATE} = "Fetching Password";

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
		Log3 $name, 2, $name . " : LG_ESS_FetchingPassword - ERROR                : ".$Service. ": No proper Communication with Gateway: " .$err;
		return "LG ESS: could not fetch password";	
	}
	elsif($data ne "") 
	{

		# Create Log entry for debugging
		Log3 $name, 5, $name . "LG_ESS_FetchingPassword Data: ".$data;

		# Decode json
		my $decodedData = decode_json($data);

		if ($decodedData->{'status'} = "success")
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
	my $Password					= $hash->{PASSWORD};
	$hash->{temp}{SERVICE}			= "User Login";

	# Stop the current timer
	RemoveInternalTimer($hash);

	# Set status of fhem module
	$hash->{STATE} = "Login";

	my $url = "https://".$ip."/v1/user/setting/login";
	my $content = '{"password": "'.$Password .'"}';

	my $sslPara->{sslargs} = { verify_hostname => 0};
	my $param = {
					url			=> $url,
					timeout		=> $PollingTimeout,
					data		=> $content,
					hash		=> $hash,
					method		=> "PUT",
					sslargs		=> $sslPara,
					header		=> "Content-Type: application/json",
					callback	=> \&LG_ESS_HttpResponseUserLogin
				};

	#Function call
	HttpUtils_NonblockingGet($param);
}

#-----------------------------------------------------------------------------------------------------------------------
# Subroutine for parsing user loging json answer and getting aut_key
#-----------------------------------------------------------------------------------------------------------------------
sub LG_ESS_HttpResponseUserLogin($)
{
	my ($param, $err, $data)	= @_;
	my $hash					= $param->{hash};
	my $name					= $hash ->{NAME};
	my $Service					= $hash->{temp}{SERVICE};

	my $type;
	my $json ->{type} = "";

	if($err ne "") 
	{
		# Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_HttpResponseUserLogin - ERROR                : ".$Service. ": No proper Communication with Gateway: " .$err;

		# Set status of fhem module
		$hash->{STATE} = "ERROR - Initial Connection failed... Try to re-connect in 10s";

		# Start the timer for polling again but wait 10s
		InternalTimer(gettimeofday()+10, "LG_ESS_UserLogin", $hash, 1);

		# Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_HttpResponseUserLogin - ERROR                : Timer restarted to try again in 10s";
		return "ERROR";	
	}
	elsif($data ne "") 
	{

		# Create Log entry for debugging
		Log3 $name, 5, $name . "LG_ESS_HttpResponseUserLogin Data: ".$data;

		# Decode json
		my $decodedData = decode_json($data);

		my $auth_key =$decodedData->{'auth_key'};
		if ($auth_key ne "failed")
		{
			$hash->{temp}{AUTH_KEY} = $auth_key;
			Log3 $name, 2, $name . " : LG_ESS_HttpResponseUserLogin - Login success! auth key:".$auth_key;
			
			$hash ->{temp}{ServiceCounterInit} = 0;
			LG_ESS_GetState($hash);
		} else
		{
			# Create Log entry
			Log3 $name, 2, $name . " : LG_ESS_HttpResponseUserLogin - Login failed!  Timer restarted to try again in 10s";

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
	my $ip					= $hash->{IP} ;
	my $name				= $hash->{NAME} ;
	my $ServiceCounterInit	= $hash ->{temp}{ServiceCounterInit};

	my $PollingTimeout		= $hash->{POLLINGTIMEOUT};
	my $Password			= $hash->{PASSWORD};
	my $auth_key			= $hash->{temp}{AUTH_KEY};
	my @state_urls			= @{$hash->{Secret}{STATE_URLS}};
	my $NumberStateUrls		= @state_urls;

	$hash->{temp}{SERVICE} = $state_urls[$ServiceCounterInit];

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
	my $IntervalDynVal			= $hash->{INTERVALDYNVAL};
	my $Service					= $hash->{temp}{SERVICE};
	my @state_urls				= @{$hash->{Secret}{STATE_URLS}};
	my $NumberStateUrls			= @state_urls;

	my $type;
	my $json ->{type} = "";

	if($err ne "") 
	{
		# Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_HttpResponseState - ERROR                : ".$Service. ": No proper Communication with Gateway: " .$err;

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
		my $valueOld;

		# Initialize Bulkupdate
		readingsBeginUpdate($hash);
		if ($Service eq "/v1/user/essinfo/common")
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
		elsif ($Service eq "/v1/user/essinfo/home")		
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
		elsif ($Service eq "/v1/user/setting/systeminfo")		
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
		elsif ($Service eq "/v1/user/setting/network")
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
		elsif ($Service eq "/v1/user/setting/batt")
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
			Log3 $name, 5, $name . " : LG_ESS_HttpResponseState - ".$Service." ".$data;
		}

		# Finish and execute Bulkupdate
		readingsEndUpdate($hash, 1);

		# If the list of state_urls has not been finished yet
		if ($ServiceCounterInit < ($NumberStateUrls-1))
		{
			#increase counter
			++$ServiceCounterInit;
			$hash ->{temp}{ServiceCounterInit} = $ServiceCounterInit;
			LG_ESS_GetState($hash);
		}
		else
		{
			#Reset counter
			$hash ->{temp}{ServiceCounterInit} = 0;

			#Start timer again
			InternalTimer(gettimeofday() + $IntervalDynVal, "LG_ESS_GetState", $hash, 1);
			Log3 $name, 4, $name. " : LG_ESS - Internal timer for Initialisation of services started again.";

			# Set status of fhem module
			$hash->{STATE} = "Standby";
		}
	}
}






###START###### Subroutine initial contact of services via HttpUtils ###########################################START####
sub LG_ESS_Cmd($$)
{
	my ($hash, $cmd)				= @_;
	my $ip							= $hash->{IP};
	my $name						= $hash->{NAME};

	my $PollingTimeout				= $hash->{POLLINGTIMEOUT};
	my $Password					= $hash->{PASSWORD};
	my $auth_key					= $hash->{temp}{AUTH_KEY};

	$hash->{temp}{SERVICE}			= $cmd;

	# Set status of fhem module
	$hash->{STATE} = $cmd;	

	my $url;
	my $content;
	if ($cmd eq "InstallerLogin")
	{
		$url = "https://".$ip."/v1/installer/login";
		$content = '{"password": "18Feichtei79&"}';
	}
	elsif ($cmd eq "EssSwitchOn")
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

	my $sslPara->{sslargs} = { verify_hostname => 0};
	my $param = {
					url			=> $url,
					timeout		=> $PollingTimeout,
					data		=> $content,
					hash		=> $hash,
					method		=> "PUT",
					sslargs		=> $sslPara,
					header		=> { "X-HTTP-Method-Override" => "PUT", "Content-Type" => "application/json" },
					callback	=> \&LG_ESS_HttpResponseState
				};

	#Function call
	HttpUtils_NonblockingGet($param);
}

1;
