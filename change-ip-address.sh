#! /bin/bash

# Change IP address atomic script
#
# This script is part of GP-WAC script based solution
# Any error/debug information is written to stderr, 
# while data to be processed further are sent to stdout
#
# Version history
# 0.1: initial version
# 0.2: handles encrypted credentials
# 0.3: receives real name=value pairs from xml2npv and parameter passing to expect is in an array (fixes an error with parameter passing)
# 0.4: expect functions are atomic, multiple expect scripts used, ping check is from bash
# 0.5: save-config is performed after logging in with new IP address. Return codes harmonised, debug level passed to expect scripts
# 0.6: common functions and parameters are now in a source include file
# 0.7: handles 5 credentials in credentials file

# Script name and version parameters
declare SCRIPTNAME=`basename "$0"`
declare SCRIPT_VERSION="v0.7.02"

# Include common functions and parameters
source "$HOME/gpwac/aux-scripts/gpwac-common-params.sh"

# Local script variables
declare EXP_CONF_SCRIPT_PATH="$HOME/gpwac/aux-scripts/configure-ip-params.exp"
declare EXP_SAVE_SCRIPT_PATH="$HOME/gpwac/aux-scripts/save-running-config.exp"
declare POST_IPCHANGE_PINGS=30
declare POST_IPCHANGE_OK_PINGS=3

# Getting command line parameters
declare -i NO_ARGS=0
declare -i DBG_LEVEL=0
declare CURR_IP_ADDR=""
declare AGE_CREDS=""
declare USER=""
declare PASSWD=""
declare XML_PATH=""
declare XSD_PATH=""
declare NEW_IP_ADDR=""

# Print usage function, no parameters
function print_usage ()
{
   (>&2 echo "Usage: `basename $0` options new-ip-address")
   (>&2 echo "       -h: help (this text)")
   (>&2 echo "       -d n: debug level (n = 0..2)")
   (>&2 echo "       -i: current ip address of device")
   (>&2 echo "       -u: user credentials for device (age encoded)")
   (>&2 echo "       -x <file>: XML file path")
   (>&2 echo "       -s <file>: XSD file path")
}


printerrmsg 0 "Change IP address atomic function - Z. Fekete (C) 2026 - Started..."

# Test if script invoked without command-line arguments
if [ $# -eq "$NO_ARGS" ]
then
   printerrmsg 0 "Error: missing command-line options"
   exit $RTN_OPTERROR
fi

while getopts "d:i:u:x:s:h" OPTION
   do
      case $OPTION in
         d ) if [ "$OPTARG" -ge 0 ] && [ "$OPTARG" -le 2 ]
            then
               DBG_LEVEL=$OPTARG
               printerrmsg 2 "Debug level is set to $DBG_LEVEL"
            else
               printerrmsg 0 "Error: Invalid debug level value: $OPTARG (allowed 0..2)"
			   exit $RTN_OPTERROR
            fi;;
         i ) CURR_IP_ADDR=$OPTARG
             printerrmsg 1 "Current IP address: $CURR_IP_ADDR";;
         u ) AGE_CREDS=$OPTARG
             printerrmsg 1 "Encrypted credentials path: $AGE_CREDS";;
         x ) XML_PATH=$OPTARG
             printerrmsg 1 "XML file path: $XML_PATH";;
         s ) XSD_PATH=$OPTARG
             printerrmsg 1 "XSD file path: $XSD_PATH";;
         h ) print_usage
		     exit $RTN_HELPONLY;;
      esac
   done
shift $(($OPTIND - 1))

if [[ ! $CURR_IP_ADDR =~ ^((1?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])$ ]]
then
	printerrmsg 0 "Error: invalid current IP address: '$CURR_IP_ADDR'"
	exit $RTN_OPTERROR
fi

if [[ "$CURR_IP_ADDR" = "" || "$AGE_CREDS" = "" || "$XML_PATH" = "" || "$XSD_PATH" = "" ]]; then
  printerrmsg 0 "Error: mandatory command line option(s) not provided"
  exit $RTN_OPTERROR
fi
if [[ ! $1 =~ ^((1?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])$ ]]
then
	printerrmsg 0 "Error: mandatory new IP address parameter missing or invalid: '$1'"
	exit $RTN_ARGERROR
fi
NEW_IP_ADDR=$1
printerrmsg 1 "New IP address: $NEW_IP_ADDR"

# Decode credentials
USERPWD=$(/usr/bin/age -d -i $AGEKEY_PATH $AGE_CREDS)
declare -i LINES=0
while IFS='=' read -r name value; do
    printf -v "$name" '%s' "$value"
	LINES=$LINES+1
done <<< "$USERPWD"

# Verify if decode is ok
if [[ $LINES -ne 5 || $USER = "" || $PASSWD = "" || $ENC_PASSWD = "" || $SFTP_USER = "" || $SFTP_PASSWD = "" ]]; then
	printerrmsg 0 "Error: user credentials file incorrect, lines: $LINES user: $USER, pwdlen: ${#PASSWD}, encrypt pwdlen: ${#ENC_PASSWD}, sftp user: $SFTP_USER, sftp pwdlen: ${#SFTP_PASSWD}"
	exit $RTN_OPTERROR
fi
printerrmsg 1 "Credentials decoded lines: $LINES user: $USER, pwdlen: ${#PASSWD}, encrypt pwdlen: ${#ENC_PASSWD}"

# Start real work here
XML_ARGS=$($XML2NVP_PATH -d $DBG_LEVEL -l $CURR_IP_ADDR -m ip -x $XML_PATH -s $XSD_PATH)
RETURN_VAL=$?

if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: when running XML parser (return value: $RETURN_VAL), exiting..."
	exit $RETURN_VAL
else
	printerrmsg 1 "XML file successfully processed (return value: $RETURN_VAL)"
fi

# Process NPV output, get each value to its own variable and construct expect argument array
EXPECT_ARGS=( "DBG_LEVEL=$DBG_LEVEL" "USER=$USER" "CURR_IP_ADDR=$CURR_IP_ADDR" "PASSWD=$PASSWD" "NEW_IP_ADDR=$NEW_IP_ADDR" $XML_ARGS )

# Check if device can be pinged on current IP address
/bin/ping -c 4 -W 1 $CURR_IP_ADDR >/dev/null
if  [ $? -ne 0 ]
then
	printerrmsg 0 "Error: device on $CURR_IP_ADDR cannot be reached. Exiting..."
	exit $RTN_PING_NORESP
else
	printerrmsg 1 "Device on $CURR_IP_ADDR reachable, continuing"
fi

# Call expect script with the necessary argument list
printerrmsg 1 "Script $EXP_CONF_SCRIPT_PATH called.."
#echo "${EXPECT_ARGS[@]}"
$EXP_CONF_SCRIPT_PATH "${EXPECT_ARGS[@]}"
RETURN_VAL=$?

if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: Expect script returned an error: $RETURN_VAL), exiting..."
	exit $RTN_CONFIG_FAILED
else
	printerrmsg 0 "Expect script successfully completed (return value: $RETURN_VAL)"
fi

printerrmsg 1 "Waiting for device settings to complete: " "nonl"

# Check device if reachable on new IP address
declare -i PING_ITER=0
declare -i PING_OK=0
while (( PING_ITER < POST_IPCHANGE_PINGS ))
do
	# Note that -c2 means actually 1 second delay (2 pings with 1 seconds in between)
    ping -c2 -W1 "$NEW_IP_ADDR" >/dev/null
	if [ $? -ne 0 ]
	then
        (>&2 echo -n ".")
    else
        (>&2 echo -n -e "*")
		if (( PING_OK < POST_IPCHANGE_OK_PINGS ))
		then
			(( PING_OK++ ))
		else
		    break
		fi
    fi
	(( PING_ITER++ ))
done
(>&2 echo -n -e "\n")

if (( PING_ITER >= POST_IPCHANGE_PINGS ))
then
	printerrmsg 0 "Error: device on $CURR_IP_ADDR cannot be reached. Exiting..( Exit code: $RTN_PING_NEW_NORESP )"
	exit $RTN_PING_NEW_NORESP
else
	printerrmsg 0 "Device on $CURR_IP_ADDR reachable."
fi

# From now on new IP address becomes the current one
CURR_IP_ADDR=$NEW_IP_ADDR

# Save the running configuration
EXPECT_ARGS=( "DBG_LEVEL=$DBG_LEVEL" "USER=$USER" "CURR_IP_ADDR=$CURR_IP_ADDR" "PASSWD=$PASSWD" )
printerrmsg 1 "Script $EXP_SAVE_SCRIPT_PATH called.."
#echo "${EXPECT_ARGS[@]}"
$EXP_SAVE_SCRIPT_PATH "${EXPECT_ARGS[@]}"
RETURN_VAL=$?

if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: Expect script returned an error: $RETURN_VAL), exiting..."
	exit $RTN_SAVE_FAILED
else
	printerrmsg 0 "Expect script successfully completed (return value: $RETURN_VAL)"
fi
#
exit $RTN_SUCCESS