#! /bin/bash
#
# Configure SSID atomic script
#
# This script is part of GP-WAC script based solution
# Any error/debug information is written to stderr, 
# while data to be processed further are sent to stdout
#
# Version history
# 0.1: initial version
#
# Backlog:
# 
#
# Script name and version parameters

declare SCRIPTNAME=`basename "$0"`
declare SCRIPT_VERSION="v0.2.00"

# Include common functions and parameters

source "$HOME/gpwac/aux-scripts/gpwac-common-params.sh"

# Local script variables
declare EXP_SSIDLIST_SCRIPT_PATH="$HOME/gpwac/aux-scripts/get-ssidlist.exp"
declare EXP_CREATESSID_SCRIPT_PATH="$HOME/gpwac/aux-scripts/create-ssid.exp"
declare EXP_MODSSID_SCRIPT_PATH="$HOME/gpwac/aux-scripts/modify-ssid.exp"
declare EXP_DELETESSID_SCRIPT_PATH="$HOME/gpwac/aux-scripts/delete-ssid.exp"
declare RECONNECT_DELAY=15

# Getting command line parameters
declare -i NO_ARGS=0
declare -i DBG_LEVEL=0
declare CURR_IP_ADDR=""
declare AGE_CREDS=""
declare USER=""
declare PASSWD=""
declare XML_PATH=""
declare XSD_PATH=""

# Print usage function, no parameters
function print_usage ()
{
   (>&2 echo "Usage: `basename $0` options")
   (>&2 echo "       -h: help (this text)")
   (>&2 echo "       -d n: debug level (n = 0..2)")
   (>&2 echo "       -i: current ip address of device")
   (>&2 echo "       -u: user credentials for device (age encoded)")
   (>&2 echo "       -x <file>: XML file path")
   (>&2 echo "       -s <file>: XSD file path")
}

printerrmsg 0 "Create or modify SSID parameters atomic function - Z. Fekete (C) 2026 - Started..."

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
TARGET_SSIDLIST=$($XML2NVP_PATH -d $DBG_LEVEL -l $CURR_IP_ADDR -m ssid -x $XML_PATH -s $XSD_PATH)
RETURN_VAL=$?
if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: when running XML parser (return value: $RETURN_VAL), exiting..."
	exit $RETURN_VAL
else
	printerrmsg 1 "XML file successfully processed (return value: $RETURN_VAL)"
fi
printerrmsg 2 "Result from Parser\n$TARGET_SSIDLIST\n" "nonl"

# Check if device can be pinged on current IP address
/bin/ping -c 4 -W 1 $CURR_IP_ADDR >/dev/null
if  [ $? -ne 0 ]
then
	printerrmsg 0 "Error: device on $CURR_IP_ADDR cannot be reached. Exiting..."
	exit $RTN_PING_NORESP
else
	printerrmsg 1 "Device on $CURR_IP_ADDR reachable, continuing"
fi

# First get the SSID list from the device
EXPECT_ARGS=( "DBG_LEVEL=$DBG_LEVEL" 
              "USER=$USER" 
			  "CURR_IP_ADDR=$CURR_IP_ADDR" 
			  "PASSWD=$PASSWD"
            )
printerrmsg 1 "Script $EXP_SSIDLIST_SCRIPT_PATH called.."
IFS=','; printerrmsg 2 "Arguments: ${EXPECT_ARGS[*]}\n" "nonl"

CURR_SSIDLIST=$(expect $EXP_SSIDLIST_SCRIPT_PATH "${EXPECT_ARGS[@]}")
RETURN_VAL=$?
if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: Expect $EXP_SSIDLIST_SCRIPT_PATH script returned an error: $RETURN_VAL), exiting..."
	exit $RTN_CONFIG_FAILED
else
	printerrmsg 1 "Expect script successfully completed (return value: $RETURN_VAL)"
fi

printerrmsg 0 "Existing SSIDs: $CURR_SSIDLIST"

# Identify the SSIDs to be deleted, modified or created based on current and target SSID lists

# Extract SSIDNAME values from TARGET_SSIDLIST into an array of TARGET_SSIDs
mapfile -t TARGET_SSIDS < <(
    echo "$TARGET_SSIDLIST" |
    awk '
        {
            ssid = ""
            band = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^SSIDNAME=/) ssid = substr($i, 10)
                if ($i ~ /^RFBAND=/)   band = substr($i, 8)
            }
            if (ssid != "" && band != "")
                print ssid " " band
        }
    '
)

# Extract CURR_SSIDS from CURR_SSIDLIST and build an array
mapfile -t CURR_SSIDS < <(
    grep -o '{[^}]*}' <<< "$CURR_SSIDLIST" | tr -d '{}'
)

# Build lookup tables
declare -A TARGET_MAP
declare -A CURR_MAP

for s in "${TARGET_SSIDS[@]}"; do
    TARGET_MAP["$s"]=1
done

if [ ${#CURR_SSIDS[@]} -eq 0 ]
then
	printerrmsg 1 "No SSIDs defined in the device (no delete/modify)"
else
	for s in "${CURR_SSIDLIST[@]}"; do
		printerrmsg 0 "SSID: $s"
		CURR_MAP["$s"]=1
	done
fi

# Start building expect argument array for SSIDs to be deleted
EXPECT_ARGS=( "DBG_LEVEL=$DBG_LEVEL" 
              "USER=$USER" 
			  "CURR_IP_ADDR=$CURR_IP_ADDR" 
			  "PASSWD=$PASSWD"
            )

printerrmsg 1 "Checking items from existing SSID list in device"
declare -i i=0
for CURR_SSID in "${CURR_SSIDS[@]}"; do
    if [[ -n "${TARGET_MAP[$CURR_SSID]}" ]]; then
        printerrmsg 1 "SSID '$CURR_SSID' exists as target SSID - kept for modification"
    else
        printerrmsg 0 "SSID '$CURR_SSID' not on target SSID list and will be deleted"
		EXPECT_ARGS+=("SSID($i)=$CURR_SSID")
		i+=1
    fi
done

# Delete SSIDs which are not on the target list (if any)
if [ ${#CURR_SSIDS[@]} -ne 0 ]
then
	printerrmsg 1 "Script $EXP_DELETESSID_SCRIPT_PATH called.."
	IFS ', '; printerrmsg 2 "Expect arguments: '${EXPECT_ARGS[*]}'"

	# Calling the Delete SSID expect script
	expect $EXP_DELETESSID_SCRIPT_PATH "${EXPECT_ARGS[@]}"
	RETURN_VAL=$?
	if [ $RETURN_VAL -ne 0 ]
	then
		printerrmsg 0 "Error: Expect $EXP_DELETESSID_SCRIPT_PATH script returned an error: $RETURN_VAL), exiting..."
		exit $RTN_CONFIG_FAILED
	else
		printerrmsg 1 "Expect script successfully completed (return value: $RETURN_VAL)"
	fi
fi

printerrmsg 1 "Checking items of target SSID list"
for TARGET_SSID in "${TARGET_SSIDS[@]}"; do
    if [[ -n "${CURR_MAP[$TARGET_SSID]}" ]]; then
        printerrmsg 0 "SSID '$TARGET_SSID' exists in the device and will be modified"
    else
        printerrmsg 0 "SSID '$TARGET_SSID' does not exist in the device and will be created"
    fi
done

# Start building expect argument array for SSIDs to be created/modified
EXPECT_ARGS=( "DBG_LEVEL=$DBG_LEVEL" 
              "USER=$USER" 
			  "CURR_IP_ADDR=$CURR_IP_ADDR" 
			  "PASSWD=$PASSWD"
            )
# Each line on the TARGET_SSIDLIST will go to a different array element
while IFS= read -r line; do
    EXPECT_ARGS+=("$line")
done <<< "$TARGET_SSIDLIST"

# Call create SSID script
printerrmsg 1 "Scripts $EXP_CREATESSID_SCRIPT_PATH started..."
IFS=','; printerrmsg 2 "Arguments: ${EXPECT_ARGS[*]}\n" "nonl"

expect $EXP_CREATESSID_SCRIPT_PATH "${EXPECT_ARGS[@]}"
RETURN_VAL=$?
if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: Expect $EEXP_CREATESSID_SCRIPT_PATH script returned an error: $RETURN_VAL), exiting..."
	exit $RTN_CONFIG_FAILED
else
	printerrmsg 1 "Expect script successfully completed (return value: $RETURN_VAL)"
fi
exit 0



#
# Process NPV output, get each value to its own variable and construct expect argument array - this is done one line at a time
#
EXPECT_ARGS=( 
	"DBG_LEVEL=$DBG_LEVEL"
	"USER=$USER"
	"CURR_IP_ADDR=$CURR_IP_ADDR"
	"PASSWD=$PASSWD"
	$TARGET_SSIDLIST
)
#
# Call expect script with the necessary argument list
#
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
printerrmsg 1 "Waiting for device settings to complete..."
sleep $RECONNECT_DELAY
#
# Check if device can be pinged on NEW IP address
#
/bin/ping -c 4 -W 1 $NEW_IP_ADDR >/dev/null
if  [ $? -ne 0 ]
then
	printerrmsg 0 "Error: device on $NEW_IP_ADDR cannot be reached. Exiting..."
	exit $RTN_PING_NEW_NORESP
else
	printerrmsg 1 "Device on $NEW_IP_ADDR reachable, continuing"
fi
#
# From now on new IP address becomes the current one
#
CURR_IP_ADDR=$NEW_IP_ADDR
#
# Save the running configuration
#
EXPECT_ARGS=( "DBG_LEVEL=$DBG_LEVEL" "USER=$USER" "CURR_IP_ADDR=$CURR_IP_ADDR" "PASSWD=$PASSWD" )
printerrmsg 1 "Script $EXP_SAVE_SCRIPT_PATH called.."
IFS ', '; printerrmsg 2 "${EXPECT_ARGS[*]}"
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