#! /bin/bash
#
# GP-WAC Simple Batch Automation Script
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
declare SCRIPT_VERSION="v0.1.00"

# Include common functions and parameters

source "$HOME/gpwac/aux-scripts/gpwac-common-params.sh"

# Local script variables

declare CHECKAP_PATH="$HOME/gpwac/check-ap.sh"
declare SETDEFCONF_PATH="$HOME/gpwac/set-default-configuration.sh"
declare CHGIP_PATH="$HOME/gpwac/change-ip-address.sh"
declare CFGSSID_PATH="$HOME/gpwac/config-ssid.sh"

# Getting command line parameters
declare -i NO_ARGS=0
declare -i DBG_LEVEL=0
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
   (>&2 echo "       -u: user credentials for device (age encoded)")
   (>&2 echo "       -x <file>: XML file path")
   (>&2 echo "       -s <file>: XSD file path")
}

# Finding out server's own address for logging
SERVER_IP_ADDR=$(ip -4 addr show dev $(ip route | awk '/default/ {print $5; exit}') | awk '/inet / {print $2}' | cut -d/ -f1)
if  [[ $? -ne 0 || ! $SERVER_IP_ADDR =~ ^((1?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])$ ]]
then
	printerrmsg 0 "Warning: Server's own IP address cannot be determined (address returned: '$SERVER_IP_ADDR'). Affects logging only."
fi

printerrmsg 0 "GP-WAC Simple Batch Automation - Z. Fekete (C) 2026 - Started..."

# Test if script invoked without command-line arguments
if [[ "$#" == "$NO_ARGS" ]]
then
   printerrmsg 0 "Error: missing command-line options"
   exit $RTN_OPTERROR
fi

while getopts "d:u:x:s:h" OPTION
   do
      case $OPTION in
         d ) if (( OPTARG >= 0 && OPTARG <= 2 ))
            then
               DBG_LEVEL=$OPTARG
               printerrmsg 2 "Debug level is set to $DBG_LEVEL"
            else
               printerrmsg 0 "Error: Invalid debug level value: $OPTARG (allowed 0..2)"
			   exit $RTN_OPTERROR
            fi;;
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

if [[ "$AGE_CREDS" = "" || "$XML_PATH" = "" || "$XSD_PATH" = "" ]]; then
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
if (( LINES != 5 )) || [[ $USER == "" || $PASSWD == "" || $ENC_PASSWD == "" || $SFTP_USER == "" || $SFTP_PASSWD == "" ]]; then
	printerrmsg 0 "Error: user credentials file incorrect, lines: $LINES user: $USER, pwdlen: ${#PASSWD}, encrypt pwdlen: ${#ENC_PASSWD}, sftp user: $SFTP_USER, sftp pwdlen: ${#SFTP_PASSWD}"
	exit $RTN_OPTERROR
fi
printerrmsg 1 "Credentials decoded lines: $LINES user: $USER, pwdlen: ${#PASSWD}, encrypt pwdlen: ${#ENC_PASSWD}"

# Start real work here - parse the XML
EXEC_LIST=$($XML2NVP_PATH -d $DBG_LEVEL -l $SERVER_IP_ADDR -m exec -x $XML_PATH -s $XSD_PATH)
RETURN_VAL=$?
if (( RETURN_VAL != 0 )); then
	printerrmsg 0 "Error: when running XML parser (return value: $RETURN_VAL), exiting..."
	exit $RETURN_VAL
else
	printerrmsg 1 "XML file successfully processed (return value: $RETURN_VAL)"
fi
printerrmsg 2 "Result from Parser\n$EXEC_LIST\n" "nonl"

# Initialise summary log and error counter variables
declare SUMMARY_LOG=""
declare -i NERRORS=0
declare -i ITEMERROR=0
declare -i LINENUMBER=0

# Cycle through all lines and process them
while IFS= read -r LINE; do

	# Assigning key value pairs to 
	for pair in $LINE; do
        key=${pair%%=*}
        value=${pair#*=}
        printf -v "$key" '%s' "$value"
    done
	
	# Reset item error variable and update line number
	ITEMERROR=0
	LINENUMBER+=1
	
	# Expand path variables
	CRED_FILE=$(printf '%s\n' "$CRED_FILE" | envsubst)
	CONFIG_DIR=$(printf '%s\n' "$CONFIG_DIR" | envsubst)
	IPXML_FILE=$(printf '%s\n' "$IPXML_FILE" | envsubst)
	IPXSD_FILE=$(printf '%s\n' "$IPXSD_FILE" | envsubst)
	SSIDXML_FILE=$(printf '%s\n' "$SSIDXML_FILE" | envsubst)
	SSIDXSD_FILE=$(printf '%s\n' "$SSIDXSD_FILE" | envsubst)

	CHECKAP_PATH=$(printf '%s\n' "$CHECKAP_PATH" | envsubst)
	SETDEFCONF_PATH=$(printf '%s\n' "$SETDEFCONF_PATH" | envsubst)
	CHGIP_PATH=$(printf '%s\n' "$CHGIP_PATH" | envsubst)
	CFGSSID_PATH=$(printf '%s\n' "$CFGSSID_PATH" | envsubst)
	
	# List parameters for debug
	printerrmsg 2 "Item processed: $LINE"
	printerrmsg 1 "***** Processing item $LINENUMBER:"
	printerrmsg 2 "** Credentials file: $CRED_FILE"
	if [[ "$DEFCONF" == "true" ]]; then
		printerrmsg 1 "** Setting default configuration from: $CONFIG_DIR"
	else
		printerrmsg 1 "** Not setting default configuration, IP settings only"
	fi
	printerrmsg 1 "** Current IP: $CUR_IP_ADDR, new IP address: $NEW_IP_ADDR"
	printerrmsg 1 "** IP settings definition: $IPXML_FILE, $IPXSD_FILE"
	printerrmsg 1 "** SSID configurations: $SSIDXML_FILE, $SSIDXSD_FILE"

	# Identity to summary log
	SUMMARY_LOG+="Item: $LINENUMBER, IP: $CUR_IP_ADDR, "
	
    # Checking device
	$CHECKAP_PATH -d $DBG_LEVEL -u $CRED_FILE -i $CUR_IP_ADDR
	RETURN_VAL=$?
	if (( RETURN_VAL != 0 )); then
		printerrmsg 0 "Error: Check Device failed (return value: $RETURN_VAL), skipping to next item"
		SUMMARY_LOG+="ChkDev: Error ($RETURN_VAL)\n"
		ITEMERROR=1
		NERRORS+=1
	else
		SUMMARY_LOG+="ChkDev: Ok, "
		printerrmsg 1 "Check Device: Ok"
	fi
	sleep 10
	
	# Setting default configuration or IP settings only
	sleep 5
	if (( ITEMERROR == 0 )); then
		if [[ "$DEFCONF" == "true" ]]; then
			$SETDEFCONF_PATH -d $DBG_LEVEL -u $CRED_FILE -i $CUR_IP_ADDR -c $CONFIG_DIR -x $IPXML_FILE -s $IPXSD_FILE $NEW_IP_ADDR
			RETURN_VAL=$?
			if (( RETURN_VAL != 0 )); then
				printerrmsg 0 "Error: Set Default Configuration failed (return value: $RETURN_VAL), skipping to next item"
				SUMMARY_LOG+="SetDefConf: Error ($RETURN_VAL)\n"
				ITEMERROR=1
				NERRORS+=1
			else
				SUMMARY_LOG+="SetDefConf: Ok, "
				printerrmsg 1 "Set Default Configuration: Ok"
			fi
		else
			$CHGIP_PATH -d $DBG_LEVEL -u $CRED_FILE -i $CUR_IP_ADDR -x $IPXML_FILE -s $IPXSD_FILE $NEW_IP_ADDR
			RETURN_VAL=$?
			if (( RETURN_VAL != 0 )); then
				printerrmsg 0 "Error: Change IP Settings failed (return value: $RETURN_VAL), skipping to next item"
				SUMMARY_LOG+="ChgIP: Error ($RETURN_VAL)\n"
				ITEMERROR=1
				NERRORS+=1
			else
				SUMMARY_LOG+="ChgIP: Ok, "
				printerrmsg 1 "Change IP Settings: Ok"
			fi
		fi
	fi
	sleep 15
	
	# Configure SSIDs and associated VLANs
	if (( ITEMERROR == 0 )); then
		$CFGSSID_PATH -d $DBG_LEVEL -u $CRED_FILE -i $NEW_IP_ADDR -x $SSIDXML_FILE -s $SSIDXSD_FILE
		RETURN_VAL=$?
		if (( RETURN_VAL != 0 )); then
			printerrmsg 0 "Error: Configure SSIDs failed (return value: $RETURN_VAL), skipping to next item"
			SUMMARY_LOG+="CfgSSID: Error ($RETURN_VAL)\n"
			ITEMERROR=1
			NERRORS+=1
		else
			SUMMARY_LOG+="CfgSSID: Ok, "
			printerrmsg 1 "Configure SSIDs: Ok"
		fi
	fi
	sleep 5
	
	# If no error then indicate that item completed ok
	if (( ITEMERROR == 0 )); then
		SUMMARY_LOG+="Item $LINENUMBER Completed, Ok\n"
		printerrmsg 1 "Item $LINENUMBER Completed, Ok"
	fi
	
done <<< "$EXEC_LIST"

printerrmsg 1 "Batch Automation script completed successfully"
echo "Summary of Batch Run:"
echo "Items processed: $LINENUMBER"
echo "Number of errors: $NERRORS"
echo "================================================================================================="
echo -n -e $SUMMARY_LOG
echo "*** End of batch run ***"

exit $NERRORS
