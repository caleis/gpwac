#! /bin/bash
#
# Encrypt credentials file
#
# This script is part of GP-WAC script based solution
# Any error/debug information is written to stderr, 
# while data to be processed further are sent to stdout
#
# Version history
# 0.1: initial version
# 0.2: encryption password added
# 0.3: sftpuser and password added
#
# Script name and version parameters
#
declare SCRIPTNAME=`basename "$0"`
declare SCRIPT_VERSION="v0.3.00"
#
# Include common functions and parameters
#
source ./gpwac-common-params.sh
#
# Local script variables
#
declare CRED_PATH=~/.gpwac/devices-cred.age
declare KEY_PATH=~/.gpwac/gpwac.age 
#
# Getting command line parameters
#
declare -i NO_ARGS=0
declare -i DBG_LEVEL=0
declare USER=""
declare PASSWD=""
declare ENC_PASSWD=""
declare SFTP_USER=""
declare SFTP_PASSWD=""
#
# Print usage function, no parameters
#
function print_usage ()
{
   (>&2 echo "Usage: `basename $0` options [credentials-file] [key-file]")
   (>&2 echo "       -h: help (this text)")
   (>&2 echo "       -d n: debug level (n = 0..2)")
   (>&2 echo "       -u: username for device")
   (>&2 echo "       -p: password for device")
   (>&2 echo "       -e: password for config file encryption")
   (>&2 echo "       -s: SFTP username (for config file upload)")
   (>&2 echo "       -q: password for SFTP user")
   (>&2 echo "       Credentials and key file name are optional, defaults: $CRED_PATH, $KEY_PATH")
} 

printerrmsg 0 "Create encrypted credentials file - Z. Fekete (C) 2026"

while getopts "d:u:p:e:s:q:h" OPTION
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
         u ) USER=$OPTARG
             printerrmsg 1 "Username: $USER";;
         p ) PASSWD=$OPTARG
             printerrmsg 1 "Password: <provided>";;
         e ) ENC_PASSWD=$OPTARG
             printerrmsg 1 "Encryption password: <provided>";;
         s ) SFTP_USER=$OPTARG
             printerrmsg 1 "SFTP user: $SFTP_USER";;
         q ) SFTP_PASSWD=$OPTARG
             printerrmsg 1 "SFTP password: <provided>";;
         h ) print_usage
		     exit $RTN_HELPONLY;;
      esac
   done
shift $(($OPTIND - 1))

# Test if script invoked with optional file name
if [ $# -gt 2 ]; then
   printerrmsg 0 "Error: two many arguments in command-line"
   exit $RTN_OPTERROR
fi
if [ $# -ge 1 ]; then
   CRED_PATH=$1
fi
if [ $# -ge 2 ]; then
   KEY_PATH=$2
fi
printerrmsg 1 "Credentials file: '$CRED_PATH', Key-file: '$KEY_PATH' shall be used"

# Check command-line options
if [[ "$USER" = "" || "$PASSWD" = "" ]]; then
  printerrmsg 0 "Error: mandatory command line option(s) not provided"
  exit $RTN_OPTERROR
fi
#
# Start real work here
#
# Extract public key
RECIPIENT=$(age-keygen -y $KEY_PATH)
printerrmsg 2 "Recipient (public key): $RECIPIENT"
echo -e -n "USER=$USER\nPASSWD=$PASSWD\nENC_PASSWD=$ENC_PASSWD\nSFTP_USER=$SFTP_USER\nSFTP_PASSWD=$SFTP_PASSWD\n" | age -r "$RECIPIENT" -o $CRED_PATH

RETURN_VAL=$?
if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: when generating credentials: $RETURN_VAL), exiting..."
	rm $CRED_PATH
	exit $RETURN_VAL
else
	printerrmsg 1 "credentials created successfully (return value: $RETURN_VAL)"
fi
# setting restricted access rights
chmod 600 $CRED_PATH
if [ $RETURN_VAL -ne 0 ]
then
	printerrmsg 0 "Error: when setting restricted access: $RETURN_VAL), exiting..."
	rm $CRED_PATH
	exit $RETURN_VAL
else
	printerrmsg 1 "Access rights set for credentials: $RETURN_VAL)"
	printerrmsg 0 "Credentials can be verified with: 'age -d -i $KEY_PATH $CRED_PATH'"
fi

exit $RTN_SUCCESS