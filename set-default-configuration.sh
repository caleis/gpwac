#! /bin/bash
#
# Set default configuration atomic script - It uses the default configuration file with updated IP parameters
#
# This script is part of GP-WAC script based solution
# Any error/debug information is written to stderr, 
# while data to be processed further are sent to stdout
#
# Version history
# 0.1: initial version
#
# Backlog: check arithmetic evaluations and [[ --> ((

# Script name and version parameters
declare SCRIPTNAME=$(basename "$0")
declare SCRIPT_VERSION="v0.1.02"

# Include common functions and parameters
source "$HOME/gpwac/aux-scripts/gpwac-common-params.sh"

# Local script variables
declare EXP_SFTP_PUT_SCRIPT_PATH="$HOME/gpwac/aux-scripts/sftp-put-file.exp"
declare -i PRE_PING_DELAY=4
declare -i POST_CONFIG_PINGS=90

# This script needs to understand expect script warning return value (so it is not an error)
declare -i RTNEXP_WARN_CFGFILE_UNCHANGED=60

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
   (>&2 echo "       -c: default configuration directory (default: $CFG_DIR)")
   (>&2 echo "       -x <file>: XML file path")
   (>&2 echo "       -s <file>: XSD file path")
}

printerrmsg 0 "Set default device configuration atomic function - Z. Fekete (C) 2026 - Started..."

# Test if script invoked without command-line arguments
if [ $# -eq "$NO_ARGS" ]
then
   printerrmsg 0 "Error: missing command-line options"
   exit $RTN_OPTERROR
fi

while getopts "d:i:u:c:x:s:h" OPTION
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
         c ) CFG_DIR=$OPTARG
             printerrmsg 1 "Default configuration files location: $CFG_DIR";;
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
#
# Verify if decode is ok
#
if [[ $LINES -ne 5 || $USER = "" || $PASSWD = "" || $ENC_PASSWD = "" || $SFTP_USER = "" || $SFTP_PASSWD = "" ]]; then
	printerrmsg 0 "Error: user credentials file incorrect, lines: $LINES user: $USER, pwdlen: ${#PASSWD}, encrypt pwdlen: ${#ENC_PASSWD}, sftp user: $SFTP_USER, sftp pwdlen: ${#SFTP_PASSWD}"
	exit $RTN_OPTERROR
fi
printerrmsg 1 "Credentials decoded lines: $LINES user: $USER, pwdlen: ${#PASSWD}, encrypt pwdlen: ${#ENC_PASSWD}"
if [[ ${#ENC_PASSWD} -lt 8 || ${#ENC_PASSWD} -gt 20 ]]; then
  printerrmsg 0 "Error: Encryption password must be 8..20 characters in length"
  exit $RTN_OPTERROR
fi


# Start real work here
XML_ARGS=$($XML2NVP_PATH -d $DBG_LEVEL -l $CURR_IP_ADDR -m cfg-nw -x $XML_PATH -s $XSD_PATH)
RETURN_VAL=$?
if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: when running XML parser (return value: $RETURN_VAL), exiting..."
	exit $RETURN_VAL
else
	printerrmsg 1 "XML file successfully processed (return value: $RETURN_VAL)"
fi

# Create temp directory and copy everything there
TEMP_CFG_DIR=$(mktemp -d)
if [ $? -ne 0 ]
then
	printerrmsg 0 "Error: when creating temporary working directory, exiting..."
	exit $RTN_TEMPDIR_ERROR
else
	printerrmsg 1 "Temporary directory created: $TEMP_CFG_DIR"
fi
cp -a "$CFG_DIR/." "$TEMP_CFG_DIR/"
if [ $? -ne 0 ]
then
	printerrmsg 0 "Error: when copying configuration template files into temporary working directory, exiting..."
	find "$TEMP_CFG_DIR" -mindepth 1 -delete
	rmdir "$TEMP_CFG_DIR"
	exit $RTN_TEMPDIR_ERROR
else
	printerrmsg 1 "Files copied to temporary working directory"
fi
rm "$TEMP_CFG_DIR/network"
if [ $? -ne 0 ]
then
	printerrmsg 0 "Error: when deleting network file from temporary directory, exiting..."
	find "$TEMP_CFG_DIR" -mindepth 1 -delete
	rmdir "$TEMP_CFG_DIR"
	exit $RTN_TEMPDIR_ERROR
fi

# Process NPV output: first assign values to variables, print the configuration snippet into variable NEW_LAN
declare -i LINES=0
while IFS='=' read -r name value; do
    printf -v "$name" '%s' "$value"
	LINES=$LINES+1
done <<< "$XML_ARGS"

NEW_LAN=$(printf "config interface 'lan'\n\toption ip_mode 'static'\n\toption ip_address '%s'\n"\
"\toption subnet_mask '%s'\n\toption default_gateway '%s'\n\toption dns_server_1 '%s'\n\toption dns_server_2 '%s'\\\n" \
"$NEW_IP_ADDR" "$NETMASK" "$DEFGW" "$DNSSERVER1" "$DNSSERVER2")

# Now replace the lan block in the original config file
SECTION="lan"
awk -v new_block="$NEW_LAN" -v section="$SECTION" '
BEGIN {
    q = sprintf("%c", 39)
    skip = 0
}

$0 == "config interface " q section q {
    print new_block
    skip = 1
    next
}

/^config / {
    skip = 0
}

!skip { print }
' $CFG_DIR/network >$TEMP_CFG_DIR/network
if [ $? -ne 0 ]
then
	printerrmsg 0 "Error: when processing configuration file network section..."
	find "$TEMP_CFG_DIR" -mindepth 1 -delete
	rmdir "$TEMP_CFG_DIR"
	exit $RTN_CFG_PROC_ERROR
else
	printerrmsg 1 "Network configuration file customised"
fi

# Compress and encrypt configuration file as required by the device
NEW_CFG_FILE="$RESULT_CFG_DIR/$(basename "$CFG_DIR")_${NEW_IP_ADDR}_$(date +%Y%m%d%H%M).7z"
find "$TEMP_CFG_DIR" -maxdepth 1 -type f -exec 7z a -p$ENC_PASSWD -mhe=on $NEW_CFG_FILE {} +
if [ $? -ne 0 ]
then
	printerrmsg 0 "Error: when processing configuration file network section..."
	find "$TEMP_CFG_DIR" -mindepth 1 -delete
	rmdir "$TEMP_CFG_DIR"
	exit $RTN_CFG_PROC_ERROR
else
	printerrmsg 0 "Network configuration file customised, file saved to $NEW_CFG_FILE"
fi

# We don't need the temporary files (updated config) and directory anymore, so deleteing it.
find "$TEMP_CFG_DIR" -mindepth 1 -delete
rmdir "$TEMP_CFG_DIR"
if  [ $? -ne 0 ]
then
	printerrmsg 0 "Error: when deleting temporary files, continuing anyway..."
	find "$TEMP_CFG_DIR" -mindepth 1 -delete
	rmdir "$TEMP_CFG_DIR"
	exit $RTN_TEMPDIR_ERROR
fi

# Copy the generated configuration file to SFTP working directory
cp -a $NEW_CFG_FILE $SFTP_WORK_DIR
if  [ $? -ne 0 ]
then
	printerrmsg 0 "Error: Could not copy config file (NEW_CFG_FILE) to SFTP working directory ($SFTP_WORK_DIR). Exiting..."
	exit $RTN_PING_NORESP
else
	printerrmsg 1 "Generated configuration file copied to SFTP working directory ($SFTP_WORK_DIR)"
fi
SFTP_FILE="$(basename "$SFTP_WORK_DIR")/$(basename "$NEW_CFG_FILE")"
echo $SFTP_FILE

# Check if device can be pinged on current IP address
/bin/ping -c 4 -W 1 $CURR_IP_ADDR >/dev/null
if  [ $? -ne 0 ]
then
	printerrmsg 0 "Error: device on $CURR_IP_ADDR cannot be reached. Exiting..."
	exit $RTN_PING_NORESP
else
	printerrmsg 1 "Device on $CURR_IP_ADDR reachable, continuing"
fi

# Finding out server's own address for SFTP command
GPWAC_IP_ADDR=$(ip -4 route get $CURR_IP_ADDR 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
if  [[ $? -ne 0 || ! $GPWAC_IP_ADDR =~ ^((1?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])$ ]]
then
	printerrmsg 0 "Error: Server's own IP address cannot be determined (address returned: '$GPWAC_IP_ADDR'). Exiting..."
	exit $RTN_NO_OWN_SERVER_ADDR
else
	printerrmsg 1 "SFTP server address used: $GPWAC_IP_ADDR"
fi

# Prepare to run the restore command in AWK
EXPECT_ARGS=(
    "DBG_LEVEL=$DBG_LEVEL"
    "USER=$USER"
    "CURR_IP_ADDR=$CURR_IP_ADDR"
    "PASSWD=$PASSWD"
    "GPWAC_IP_ADDR=$GPWAC_IP_ADDR"
    "SFTP_USER=$SFTP_USER"
    "SFTP_PASSWD=$SFTP_PASSWD"
    "SFTP_FILE=$SFTP_FILE"
    "ENC_PASSWD=$ENC_PASSWD"
)

# Call expect script with the necessary argument list
printerrmsg 1 "Script $EXP_SFTP_PUT_SCRIPT_PATH called.."
$EXP_SFTP_PUT_SCRIPT_PATH "${EXPECT_ARGS[@]}"
RETURN_VAL=$?
if (( RETURN_VAL != 0 ))
then
	if (( RETURN_VAL == RTNEXP_WARN_CFGFILE_UNCHANGED ))
	then
		printerrmsg 0 "Warning: configuration not changed, no update was necessary - continuing"
	else
		printerrmsg 0 "Error: Expect script returned an error: $RETURN_VAL), exiting..."
		rm /home/$SFTP_USER/$SFTP_FILE
		exit $RTN_CONFIG_FAILED
	fi
else
	printerrmsg 0 "Expect script successfully completed (return value: $RETURN_VAL)"
fi
printerrmsg 1 "Waiting for device settings to complete..."

# From now on new IP address becomes the current one
CURR_IP_ADDR=$NEW_IP_ADDR

# First let's wait a couple of seconds, because if IP has not changed, the device is still available for a short while before reboot starts
sleep $PRE_PING_DELAY

# Check if device can be pinged on NEW IP address
printerrmsg 1 "Pinging: " "nonl"
declare -i PING_ITER=0
while (( PING_ITER < POST_CONFIG_PINGS ))
do
    ping -c3 -W1 "$CURR_IP_ADDR" >/dev/null
	if [ $? -ne 0 ]
	then
        (>&2 echo -n ".")
    else
        (>&2 echo -n -e "*\n")
		break
    fi
	(( PING_ITER++ ))
done
if (( PING_ITER >= POST_CONFIG_PINGS ))
then
	printerrmsg 0 "Error: device on $CURR_IP_ADDR cannot be reached. Exiting..( Exit code: $RTN_PING_NEW_NORESP )"
	exit $RTN_PING_NEW_NORESP
else
	printerrmsg 0 "Device on $CURR_IP_ADDR reachable. Script completed successfully"
fi
exit $RTN_SUCCESS
