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
declare SCRIPT_VERSION="v0.3.00"

# Include common functions and parameters

source "$HOME/gpwac/aux-scripts/gpwac-common-params.sh"

# Local script variables
declare EXP_SSIDLIST_SCRIPT_PATH="$HOME/gpwac/aux-scripts/get-ssidlist.exp"
declare EXP_CREATEMODSSID_SCRIPT_PATH="$HOME/gpwac/aux-scripts/createmod-ssid.exp"
declare EXP_DELETESSID_SCRIPT_PATH="$HOME/gpwac/aux-scripts/delete-ssid.exp"
declare EXP_GETSSIDVLANS_SCRIPT_PATH="$HOME/gpwac/aux-scripts/get-ssidvlans.exp"
declare EXP_MODSSIDVLANS_SCRIPT_PATH="$HOME/gpwac/aux-scripts/mod-ssidvlans.exp"
declare RECONNECT_DELAY=15
declare REINIT_DELAY=10

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

printerrmsg 2 "Existing SSIDs as returned from expect script: $CURR_SSIDLIST"

# Identify the SSIDs to be deleted, modified or created based on current and target SSID lists

# Extract CURR_SSIDS from CURR_SSIDLIST and build an array
mapfile -t CURR_SSIDS <<< $CURR_SSIDLIST

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
                print band "/" ssid
        }
    '
)

IFS=' '; printerrmsg 0 "Existing SSIDs: ${CURR_SSIDS[*]}"
IFS=' '; printerrmsg 0 "Target SSIDs: ${TARGET_SSIDS[*]}"


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
	for s in "${CURR_SSIDS[@]}"; do
		printerrmsg 2 "SSID: $s added to existing SSID list"
		CURR_MAP["$s"]=1
	done
fi

# Print map for serious debug
printerrmsg 2 "Printing existing SSID map array:"
for i in "${!CURR_MAP[@]}"; do
    printerrmsg 2 "[$i] = ${CURR_MAP[$i]}"
done

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
		# re-format SSID from rfband/ssidname to 'ssidname rfband'
		IFS='/' read -r RFBAND SSIDNAME <<< "$CURR_SSID"
		EXPECT_ARGS+=("SSID($i)=$SSIDNAME $RFBAND")
		i+=1
    fi
done

# Check if any SSIDs identified for deletion and delete
if (( i > 0 )); then
	printerrmsg 1 "Script $EXP_DELETESSID_SCRIPT_PATH called.."
	IFS=', '; printerrmsg 2 "Expect arguments: '${EXPECT_ARGS[*]}'"

	# Calling the Delete SSID expect script
	expect $EXP_DELETESSID_SCRIPT_PATH "${EXPECT_ARGS[@]}"
	RETURN_VAL=$?
	if [ $RETURN_VAL -ne 0 ]; then
		printerrmsg 0 "Error: Expect $EXP_DELETESSID_SCRIPT_PATH script returned an error: $RETURN_VAL), exiting..."
		exit $RTN_SSID_DELETE_FAILED
	else
		printerrmsg 1 "Expect script successfully completed (return value: $RETURN_VAL)"
	fi
fi

printerrmsg 1 "Checking items of target SSID list"

# Start building expect argument array for SSIDs to be modified
EXPECT_ARGS=( "DBG_LEVEL=$DBG_LEVEL" 
			  "USER=$USER" 
			  "CURR_IP_ADDR=$CURR_IP_ADDR" 
			  "PASSWD=$PASSWD"
			)

# CREATE variable will tell expect script if SSID needs to be created (1) or modified (0)
declare -i CREATE=0

# Attach the target list variable to fd 3
exec 3<<< "$TARGET_SSIDLIST"

# Cycle through the target list to build argument array for expect script
printerrmsg 1 "Checking target SSIDs for modification or creation"
for TARGET_SSID in "${TARGET_SSIDS[@]}"; do
	printerrmsg 2 "Target SSID: $TARGET_SSID, map of existing SSIDs for that target: ${CURR_MAP[$TARGET_SSID]}"
    if [[ -n "${CURR_MAP[$TARGET_SSID]}" ]]; then
        printerrmsg 0 "SSID '$TARGET_SSID' exists in the device and will be modified"
		CREATE=0
    else
        printerrmsg 0 "SSID '$TARGET_SSID' does not exist in the device and will be created"
		CREATE=1
    fi
	
	# read next line from argument list and append to expect argument list
	read -r LINE <&3
	EXPECT_ARGS+=("CREATE=$CREATE $LINE")
done

# Close fd
exec 3<&-

# Call create SSID script
printerrmsg 1 "Scripts $EXP_CREATEMODSSID_SCRIPT_PATH started..."
IFS=','; printerrmsg 2 "Arguments: ${EXPECT_ARGS[*]}\n" "nonl"

expect $EXP_CREATEMODSSID_SCRIPT_PATH "${EXPECT_ARGS[@]}"
RETURN_VAL=$?
if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: Expect $EXP_CREATEMODSSID_SCRIPT_PATH script returned an error: $RETURN_VAL), exiting..."
	exit $RTN_SSID_CREATE_MOD_FAILED
else
	printerrmsg 1 "Expect script $EXP_CREATEMODSSID_SCRIPT_PATH successfully completed (return value: $RETURN_VAL)"
fi

printerrmsg 1 "Waiting to re-initialise"
sleep $REINIT_DELAY

# List SSIDs as operation completed
EXPECT_ARGS=( "DBG_LEVEL=$DBG_LEVEL" 
              "USER=$USER" 
			  "CURR_IP_ADDR=$CURR_IP_ADDR" 
			  "PASSWD=$PASSWD"
            )
printerrmsg 1 "Script $EXP_GETSSIDVLANS_SCRIPT_PATH called.."
IFS=','; printerrmsg 2 "Arguments: ${EXPECT_ARGS[*]}\n" "nonl"

SSIDVLANS_RAW=$(expect $EXP_GETSSIDVLANS_SCRIPT_PATH "${EXPECT_ARGS[@]}")
RETURN_VAL=$?
if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: Expect $EXP_GETSSIDVLANS_SCRIPT_PATH script returned an error: $RETURN_VAL), exiting..."
	exit $RTN_SSID_MOD_VLANS_FAILED
else
	printerrmsg 1 "Expect script successfully completed (return value: $RETURN_VAL)"
fi

printerrmsg 2 "Raw message\n%s\n" $SSIDVLANS_RAW
#printf '%s\n' "$SSIDVLANS_RAW" | tr -d '\r' | awk '{ print "[" NR "] " $0 }'

# Process VLANs list
mapfile -t SSIDVLANS < <(
    printf '%s\n' "$SSIDVLANS_RAW" |
    tr -d '\r' |
    awk '
    /^SSID-[0-9.]+[[:space:]]+GHz:/ {
        mode = $(NF-1)
        pvid = $NF
        line = $0

        sub(/^SSID-/, "", line)
        sub(/[[:space:]]+(access|hybrid|trunk)[[:space:]]+[0-9]+[[:space:]]*$/, "", line)

        split(line, a, "GHz: ")
        band = a[1]
        ssid = a[2]

        gsub(/^[[:space:]]+|[[:space:]]+$/, "", band)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", ssid)

        print "SSIDNAME=" ssid " RFBAND=" band "ghz VLANMODE=" mode " CURR_PVID=" pvid
    }'
)
# Print map for serious debug
printerrmsg 2 "Processed SSID VLAN list:"
for i in "${!SSIDVLANS[@]}"; do
    printerrmsg 2 "[$i] = ${SSIDVLANS[$i]}"
done

# Now extract the target PVID list (it will be in the same order as target SSID list)
mapfile -t TARGET_PVIDS < <(
    echo "$TARGET_SSIDLIST" |
    awk '
        {
            pvid = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^PVID=/) pvid = substr($i, 6)
            }
            if (pvid != "")
                print pvid
        }
    '
)

# Print the target SSID/PVID list (content should be the same as the current SSID list, but order can be different)
printerrmsg 2 "Target SSID VLAN list:"
for i in "${!TARGET_SSIDS[@]}"; do
    printerrmsg 2 "[$i] = ${TARGET_SSIDS[$i]} --> ${TARGET_PVIDS[$i]}"
done

# Start building expect argument array for SSID VLAN modifications
EXPECT_ARGS=( "DBG_LEVEL=$DBG_LEVEL" 
			  "USER=$USER" 
			  "CURR_IP_ADDR=$CURR_IP_ADDR" 
			  "PASSWD=$PASSWD"
			)

printerrmsg 1 "SSID to VLAN assignments"

for i in "${!TARGET_SSIDS[@]}"; do
	for j in "${!SSIDVLANS[@]}"; do
		# Process current SSID parameters into variables
		IFS=' '
		for pair in ${SSIDVLANS[$j]}; do
			key=${pair%%=*}
			value=${pair#*=}
			printf -v "$key" '%s' "$value"
		done
		if [[ "$RFBAND/$SSIDNAME" == ${TARGET_SSIDS[$i]} ]]; then
			# Now add parameter list to array
			EXPECT_ARGS+=("VAP=${TARGET_SSIDS[$i]} VLANMODE=$VLANMODE CURR_PVID=$CURR_PVID TARGET_PVID=${TARGET_PVIDS[$i]}")
			printerrmsg 1 "Target[$i] Current[$j]: VAP=${TARGET_SSIDS[$i]}, CURR_PVID=$CURR_PVID, TARGET_PVID=${TARGET_PVIDS[$i]}"
		fi
	done
done

printerrmsg 1 "Scripts $EXP_MODSSIDVLANS_SCRIPT_PATH started..."
IFS=','; printerrmsg 2 "Arguments: ${EXPECT_ARGS[*]}\n" "nonl"

expect $EXP_MODSSIDVLANS_SCRIPT_PATH "${EXPECT_ARGS[@]}"
RETURN_VAL=$?
if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: Expect $EXP_MODSSIDVLANS_SCRIPT_PATH script returned an error: $RETURN_VAL), exiting..."
	exit $RTN_SSID_MOD_VLANS_FAILED
else
	printerrmsg 1 "Expect script successfully completed (return value: $RETURN_VAL)"
fi

printerrmsg 1 "SSID configuration script completed successfully"
exit $RTN_SUCCESS
