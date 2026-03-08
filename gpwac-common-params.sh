#! /bin/bash
#
# Common functions and parameters include file - this script cannot be run from console!
#
#
# Version history
# 0.1: initial version
#
declare COMMONPARAMS_VERSION="v0.1.03"
#
# Supported models (as identified by the device, in space separated list)
declare SUPPORTED_MODELS="AWK-3252A-UN  AWK-3252A-UN"

# GP-WAC components file locations
declare XML2NVP_PATH="./xml2nvp"
declare AGEKEY_PATH=~/.gpwac/gpwac.age
declare CFG_DIR="~/gpwac/default-configs/masterconfig"
declare RESULT_CFG_DIR="$HOME/gpwac/generated-configs"
declare SFTP_WORK_DIR="/home/sftpuser/cfgfiles"

# Return values
declare -i RTN_SUCCESS=0
declare -i RTN_OPTERROR=10
declare -i RTN_ARGERROR=11
declare -i RTN_HELPONLY=12
declare -i RTN_PING_NORESP=20
declare -i RTN_GETMODEL_FAILED=21
declare -i RTN_WRONG_MODEL=22
declare -i RTN_CONFIG_FAILED=23
declare -i RTN_PING_NEW_NORESP=24
declare -i RTN_SAVE_FAILED=25
declare -i RTN_TEMPDIR_ERROR=26
declare -i RTN_CFG_PROC_ERROR=27
declare -i RTN_NO_OWN_SERVER_ADDR=28

# Print diagnostic and error messages to stderr
# $1: diagnostic level. Message printed if parameter <= set debug level
# $2: message to be printed
# $3: if exists and value is "nonl" then does not print newline at the end of the line, but allows control characters
function printerrmsg ()
{
   declare DATE=$(date '+%Y-%m-%d %H:%M:%S')
   if (( $# < 2 ))
   then
      (>&2 echo "*** Error: printerrmsg called with insufficient arguments")
      return 0
   fi
   if (( (($1)) <= DBG_LEVEL ))
   then
	  if (( $# == 2 ))
	  then
		 (>&2 echo "@$DATE: [$SCRIPTNAME | $SCRIPT_VERSION | $CURR_IP_ADDR] $2")
		 return 0
	  fi
      if [[ "$3" -eq "nonl" ]]
	  then
         (>&2 echo -n -e "@$DATE: [$SCRIPTNAME | $SCRIPT_VERSION | $CURR_IP_ADDR] $2")
	  fi
   fi
}

# End of common functions and parameters