#!/bin/busybox sh
# shellcheck disable=2034
# File    : lib_logfile.sh
# Brief   : Utility functions for logging messages in shell scripts.
# Author  : Martin Rizzo | <martinrizzo@gmail.com>
# Date    : Apr 8, 2024
# Repo    : https://github.com/martin-rizzo/QuickSambaServer
# License : MIT
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#                            QuickSambaServer
#         A lightweight, easy-to-configure Samba server using Docker
#
#     Copyright (c) 2024 Martin Rizzo
#
#     Permission is hereby granted, free of charge, to any person obtaining
#     a copy of this software and associated documentation files (the
#     "Software"), to deal in the Software without restriction, including
#     without limitation the rights to use, copy, modify, merge, publish,
#     distribute, sublicense, and/or sell copies of the Software, and to
#     permit persons to whom the Software is furnished to do so, subject to
#     the following conditions:
#
#     The above copyright notice and this permission notice shall be
#     included in all copies or substantial portions of the Software.
#
#     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#     EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
#     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
#     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
#     TORT OR OTHERWISE, ARISING FROM,OUT OF OR IN CONNECTION WITH THE
#     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
#
# FUNCTIONS:
#   - set_logfile()    : Set the logfile to store the messages.
#   - message()        : Display and log a regular message.
#   - warning()        : Display and log a warning message.
#   - error()          : Display and log an error message.
#   - fatal_error()    : Display and log a fatal error message and exits the script
#   - internal_error() : Display and log a fatal internal error and exits the script
#

# CONSTANTS
RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
BLUE='\e[1;34m'
PURPLE='\e[1;35m'
CYAN='\e[1;36m'
DEFAULT_COLOR='\e[0m'

# GLOBAL INTERNAL VARS
LIB_LOG_FILE=
LIB_LOG_PADDING='   '

#============================ LOG CONFIGURATION ============================#

# Set the logfile to store messages generated by the functions:
# message, warning, error, and fatal_error.
#
# Usage:
#   set_logfile <logfile>
#
# Example:
#   set_logfile '/appdata/log/server.log'
#
set_logfile() {
    local logfile=$1
    local logdir
    [[ -z "$logfile" ]] && fatal_error "set_logfile() requires a parameter with the filename"

    # create necessary directory for log files
    logdir=$(dirname "$logfile")
    if [[ ! -d "$logdir" ]]; then
        message "Creating directory for log files: $logdir"
        run_as_user "mkdir -p \"$logdir\""
    fi

    # create QuickFtpServer's own log file
    LIB_LOG_FILE="$logfile"
    if [[ ! -e $LIB_LOG_FILE ]]; then
        run_as_user "touch \"$LIB_LOG_FILE\""
        message "Log file created: $LIB_LOG_FILE"
    fi
}

#=========================== DISPLAYING MESSAGES ===========================#

# Display and log a regular message
message() {
    case "$1" in
        '{')
            LIB_LOG_PADDING="    $LIB_LOG_PADDING"
            ;;
        '}')
            LIB_LOG_PADDING=${LIB_LOG_PADDING#    }
            ;;
        *)
            local message=$1 timestamp
            timestamp=$(date +"%Y-%m-%d %H:%M:%S")
            echo -e "${LIB_LOG_PADDING}${GREEN}>${DEFAULT_COLOR} $message" >&2
            if [[ -n "$LIB_LOG_FILE" ]]; then
                echo "$timestamp - $message" >> "$LIB_LOG_FILE"
            fi
            ;;
    esac
}

# Display and log a warning message
warning() {
    local message=$1 timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${CYAN}[${YELLOW}WARNING${CYAN}]${YELLOW} $message${DEFAULT_COLOR}" >&2
    if [[ -n "$LIB_LOG_FILE" ]]; then
        echo "$timestamp - WARNING: $message" >> "$LIB_LOG_FILE"
    fi
}

# Display and log an error message
error() {
    local message=$1 timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${CYAN}[${RED}ERROR${CYAN}]${RED} $message.${DEFAULT_COLOR}" >&2
    if [[ -n "$LIB_LOG_FILE" ]]; then
        echo "$timestamp - ERROR: $message" >> "$LIB_LOG_FILE"
    fi
}

# Displays a fatal error message and exits the script with status code 1
fatal_error() {
    local error_message=$1
    error "$error_message"
    shift

    # print informational messages, if any were provided
    while [[ $# -gt 0 ]]; do
        local info_message=$1
        echo -e " ${CYAN}\xF0\x9F\x9B\x88  $info_message.${DEFAULT_COLOR}" >&2
        shift
    done
    exit 1
}

# Displays a fatal internal error message and exits the script with code 1.
# This function is intended to be called when an unexpected error occurs,
# indicating to the user that the error is likely due to a coding mistake.
internal_error() {
    fatal_error "$1" 'This is an internal error likely caused by a mistake in the code'
}
