#! /bin/bash
#
# Check access point availability and model atomic script
#
# This script is part of GP-WAC script based solution
# Any error/debug information is written to stderr, 
# while data to be processed further are sent to stdout
#
# Version history
# 0.1: initial version
#
# 
#
# Script name and version parameters

declare SCRIPTNAME=`basename "$0"`
declare SCRIPT_VERSION="v0.1.00"

# Include common functions and parameters

source ./gpwac-common-params.sh

# Local script variables
declare EXP_GETMODEL_SCRIPT_PATH="./get-awkmodel.exp"

# Getting command line parameters
declare -i NO_ARGS=0
declare -i DBG_LEVEL=0
declare CURR_IP_ADDR=""
declare AGE_CREDS=""
declare USER=""
declare PASSWD=""

# Print usage function, no parameters
function print_usage ()
{
   (>&2 echo "Usage: `basename $0` options")
   (>&2 echo "       -h: help (this text)")
   (>&2 echo "       -d n: debug level (n = 0..2)")
   (>&2 echo "       -i: current ip address of device")
   (>&2 echo "       -u: user credentials for device (age encoded)")
}

printerrmsg 0 "Check AP avaialability and model atomic function - Z. Fekete (C) 2026 - Started..."

# Test if script invoked without command-line arguments
if [ $# -eq "$NO_ARGS" ]
then
   printerrmsg 0 "Error: missing command-line options"
   exit $RTN_OPTERROR
fi

while getopts "d:i:u:h" OPTION
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

if [[ "$CURR_IP_ADDR" = "" || "$AGE_CREDS" = "" ]]; then
  printerrmsg 0 "Error: mandatory command line option(s) not provided"
  exit $RTN_OPTERROR
fi

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

# Start real work here - parse the XML

# Check if device can be pinged on current IP address
/bin/ping -c 4 -W 1 $CURR_IP_ADDR >/dev/null
if  [ $? -ne 0 ]
then
	printerrmsg 0 "Error: device on $CURR_IP_ADDR cannot be reached. Exiting..."
	exit $RTN_PING_NORESP
else
	printerrmsg 1 "Device on $CURR_IP_ADDR reachable, continuing"
fi

# Get model next
EXPECT_ARGS=( "DBG_LEVEL=$DBG_LEVEL" 
              "USER=$USER" 
			  "CURR_IP_ADDR=$CURR_IP_ADDR" 
			  "PASSWD=$PASSWD"
            )
printerrmsg 1 "Script $EXP_GETMODEL_SCRIPT_PATH called.."
#echo "${EXPECT_ARGS[@]}"

DEVINFO=$(expect $EXP_GETMODEL_SCRIPT_PATH "${EXPECT_ARGS[@]}")
RETURN_VAL=$?
if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: Expect $EX_GETMODEL_SCRIPT_PATH script returned an error: $RETURN_VAL)"
	printerrmsg 0 "Getting model failed, device unsuported ($RTN_GETMODEL_FAILED)"
	exit $RTN_GETMODEL_FAILED
else
	printerrmsg 1 "Expect script successfully completed (return value: $RETURN_VAL)"
fi

printerrmsg 2 "Raw devinfo: $DEVINFO"

# Get device information key=value pairs into distinct variables
declare -i LINES=0
while IFS='=' read -r name value; do
    printf -v "$name" '%s' "$value"
	LINES=$LINES+1
done <<< "$DEVINFO"

printerrmsg 0 "Device $AWK_MODEL region: $AWK_REGION Serial no: $AWK_SERIALNO MAC: $AWK_MAC FW: $AWK_FWVER"

# Check if model is on supported list
for item in $SUPPORTED_MODELS; do
    if [[ "$AWK_MODEL" == "$item" ]]; then
        printerrmsg 0 "Device is supported ($AWK_MODEL)"
        exit $RTN_SUCCESS
    fi
done

# Unsupported model here
printerrmsg 0 "Device model $AWK_MODEL not on supported list: $SUPPORTED_MODELS"
exit $RTN_WRONG_MODEL
