# $Id: 73_GasTank.pm 12279 2016-10-05 18:40:55Z sailor-fhem $
########################################################################################################################
#
#     73_GasTank.pm
#     Observes a reading of a device which represents the actual counter (e.g. OW_devive) 
#     acting as gas counter, calculates the corresponding values and writes them back to 
#     the counter device.
#     Written and best viewed with Notepad++ v.6.8.6; Language Markup: Perl
#
#     Author                     : Matthias Deeke 
#     e-mail                     : matthias.deeke(AT)deeke(PUNKT)eu
#     Fhem Forum                 : http://forum.fhem.de/index.php/topic,47909.0.html
#     Fhem Wiki                  : Not yet implemented
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#     fhem.cfg: define <devicename> SolarUtils <regexp>
#
#     Example 1:
#     define myGasTank SolarUtils mySolarCounter:CounterA.*
#
########################################################################################################################

########################################################################################################################
# List of open Problems / Issues:
#
#	- set command to create Plots automatically
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
    $hash->{GetFn}           	= "LG_ESS_Get";
	$hash->{SetFn}           	= "LG_ESS_Set";
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
	InternalTimer(gettimeofday()+10, "LG_ESS_Login", $hash, 1);
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
	
	my $availableCmds = "SwitchOff ";
	$availableCmds.="GetState ";

	if($cmd eq "GetState")
	{
		LG_ESS_GetState($hash);		
	}
	elsif($cmd eq "SwitchOff")
	{	
		LG_ESS_SwitchOff($hash);
	}
	
	return $availableCmds if($cmd eq "?");

}
####END####### Manipulate reading after "set" command by fhem ##################################################END#####

###START###### Subroutine initial contact of services via HttpUtils ###########################################START####
sub LG_ESS_Login($)
{
	my ($hash, $def)                 = @_;
	my $ip           				 = $hash->{IP} ;
	my $name                         = $hash->{NAME} ;

	my $PollingTimeout               = $hash->{POLLINGTIMEOUT};
	my $Password                     = $hash->{PASSWORD};
	$hash->{temp}{SERVICE}           = "LOGIN";
	
	### Stop the current timer
	RemoveInternalTimer($hash);

	### Set status of fhem module
	$hash->{STATE} = "Login";	
	### Log file entry for debugging
	Log3 $name, 5, $name. "Login to LG ESS Home";
	
	my $url = "https://".$ip."/v1/user/setting/login";
	my $sslPara->{sslargs} = { verify_hostname => 0};
	my $content = '{"password": "'.$Password .'"}';
	
	### Get the values
	my $param = {
					url        => $url,
					timeout    => $PollingTimeout,
					data	   => $content,
					hash       => $hash,
					method     => "PUT",
					sslargs    => $sslPara,
					header     => "Content-Type: application/json",
					callback   =>  \&LG_ESS_ParseHttpResponseInit
				};
	
	
	### Get the value
	HttpUtils_NonblockingGet($param);
}
####END####### Subroutine initial contact of services via HttpUtils ############################################END#####


###START###### Subroutine initial contact of services via HttpUtils ###########################################START####
sub LG_ESS_SwitchOff($)
{
	my ($hash, $def)                 = @_;
	my $ip           				 = $hash->{IP} ;
	my $name                         = $hash->{NAME} ;

	my $PollingTimeout               = $hash->{POLLINGTIMEOUT};
	my $Password                     = $hash->{PASSWORD};
	my $auth_key                     = $hash->{temp}{AUTH_KEY};
	$hash->{temp}{SERVICE}           = "Switch off";

	### Set status of fhem module
	$hash->{STATE} = "Switch off";	
	### Log file entry for debugging
	Log3 $name, 5, $name. "Switch ESS off";
	
	#my $url = "https://".$ip."/v1/user/operation/status";
	#my $content = '{"auth_key": "'.$auth_key .'","operation": "stop"}';
	#my $content = '{"auth_key": "'.$auth_key .'","operation": "start"}';	
	
	my $url = "https://".$ip."/v1/user/setting/batt";
	my $content = '{"auth_key": "'.$auth_key .'","alg_setting": "off"}';
	
	### Get the values
	my $sslPara->{sslargs} = { verify_hostname => 0};
	my $param = {
					url        => $url,
					timeout    => $PollingTimeout,
					data	   => $content,
					hash       => $hash,
					method     => "PUT",
					sslargs    => $sslPara,
					header     => "Content-Type: application/json",
					callback   =>  \&LG_ESS_ParseHttpResponseInit
				};
	
	
	### Get the value
	HttpUtils_NonblockingGet($param);
}
####END####### Subroutine initial contact of services via HttpUtils ############################################END#####









###START###### Subroutine initial contact of services via HttpUtils ###########################################START####
sub LG_ESS_GetState($)
{
	my ($hash, $def)                 = @_;
	my $ip           				 = $hash->{IP} ;
	my $name                         = $hash->{NAME} ;
	my $ServiceCounterInit       	 = $hash ->{temp}{ServiceCounterInit};

	my $PollingTimeout               = $hash->{POLLINGTIMEOUT};
	my $Password                     = $hash->{PASSWORD};
	my $auth_key                     = $hash->{temp}{AUTH_KEY};
	my @state_urls                   = @{$hash->{Secret}{STATE_URLS}};
	my $NumberStateUrls				 = @state_urls;

	$hash->{temp}{SERVICE} = $state_urls[$ServiceCounterInit];

	my $url = "https://".$ip.$state_urls[$ServiceCounterInit];
	my $sslPara->{sslargs} = { verify_hostname => 0};
	my $content = '{"auth_key": "'.$auth_key .'"}';
	
	### Get the values
	my $param = {
					url        => $url,
					timeout    => $PollingTimeout,
					data	   => $content,
					hash       => $hash,
					method     => "POST",
					sslargs    => $sslPara,
					header     => "Content-Type: application/json",
					callback   =>  \&LG_ESS_ParseHttpResponseInit
				};
	
	### Set status of fhem module
	$hash->{STATE} = "Polling";
	
	### Get the value
	HttpUtils_NonblockingGet($param);
}
####END####### Subroutine initial contact of services via HttpUtils ############################################END#####





###START###### Subroutine to download complete initial data set from gateway ##################################START####
# For all known, but not excluded services by attribute "DoNotPoll", try reading the respective values from gateway
sub LG_ESS_ParseHttpResponseInit($)
{
    my ($param, $err, $data)     = @_;
    my $hash                     = $param->{hash};
    my $name                     = $hash ->{NAME};
	my $ServiceCounterInit       = $hash ->{temp}{ServiceCounterInit};
	my $IntervalDynVal         	 = $hash->{INTERVALDYNVAL};
	my $Service                  = $hash->{temp}{SERVICE};
	my @state_urls               = @{$hash->{Secret}{STATE_URLS}};
	my $NumberStateUrls			 = @state_urls;
	
	my $type;
    my $json ->{type} = "";
	
	if($err ne "") 
	{
		### Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_ParseHttpResponseInit - ERROR                : ".$Service. ": No proper Communication with Gateway: " .$err;
		
		### Set status of fhem module
		$hash->{STATE} = "ERROR - Initial Connection failed... Try to re-connect in 10s";
		
		### Start the timer for polling again but wait 10s
		InternalTimer(gettimeofday()+10, "LG_ESS_Login", $hash, 1);
		
		### Create Log entry
		Log3 $name, 2, $name . " : LG_ESS_ParseHttpResponseInit - ERROR                : Timer restarted to try again in 10s";
		Log3 $name, 5, $name . "______________________________________________________________________________________________________________________";
		return "ERROR";	
	}
    elsif($data ne "") 
	{	
	
		Log3 $name, 5, $name . "LG_ESS_ParseHttpResponseInit Data: ".$data;
		if ($data =~ m/auth_key failed/i)
		{
			### Create Log entry
			Log3 $name, 2, $name . " : LG_ESS_ParseHttpResponseInit - Login failed!  Timer restarted to try again in 10s";
			
			### Set status of fhem module
			$hash->{STATE} = "ERROR - Login failed... Try to re-connect in 10s";
		
			### Start the timer for polling again but wait 10s
			InternalTimer(gettimeofday()+10, "LG_ESS_Login", $hash, 1);	
		}	
		
		my $decodedData = decode_json($data);
		
		my $record;	
		my $key;
		my $key1;
		my $varName;
		my $value;
		my $valueOld;
		
		if($Service eq "LOGIN")
		{
			my $auth_key =$decodedData->{'auth_key'};
			if ($auth_key ne "failed")
			{
				$hash->{temp}{AUTH_KEY} = $auth_key;
				Log3 $name, 2, $name . " : LG_ESS_ParseHttpResponseInit - Login success! auth key:".$auth_key;
				
				$hash ->{temp}{ServiceCounterInit} = 0;
				LG_ESS_GetState($hash);
			}

		} else 
		{	

			### Initialize Bulkupdate
			readingsBeginUpdate($hash);
				
			if ($Service eq "/v1/user/essinfo/common")		
			{		
				foreach $record ($decodedData) {
					foreach $key (keys(%$record)) {
						eval{
							foreach $key1 (keys %{$record->{$key}} ){
								$varName ="/essinfo/common/".$key."/".$key1;
								$value = $record->{$key}{$key1};
								### Write Reading
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
								### Write Reading
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
								### Write Reading
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
							### Write Reading
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
							### Write Reading
							readingsBulkUpdate($hash, $varName, $value, 1);
						}
					}
				}
			}
			else
			{
				print $data;
			}
					
			### Finish and execute Bulkupdate
			readingsEndUpdate($hash, 1);
			
			### If the list of state_urls has not been finished yet
			if ($ServiceCounterInit < ($NumberStateUrls-1))
			{
				++$ServiceCounterInit;		
				$hash ->{temp}{ServiceCounterInit} = $ServiceCounterInit;
				LG_ESS_GetState($hash);
			}
			else
			{
				$hash ->{temp}{ServiceCounterInit} = 0;
				###START###### Initiate the timer for first time polling of  values from LG_ESS but wait 10s ###############START####
				InternalTimer(gettimeofday() + $IntervalDynVal, "LG_ESS_GetState", $hash, 1);
				Log3 $name, 4, $name. " : LG_ESS - Internal timer for Initialisation of services started again.";
				####END####### Initiate the timer for first time polling of  values from LG_ESS but wait 10s ################END#####
				### Set status of fhem module
				$hash->{STATE} = "Standby";
			}
				
		}
	}
}
####END####### Subroutine to download complete initial data set from gateway ###################################END#####


1;
