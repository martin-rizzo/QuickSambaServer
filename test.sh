#!/usr/bin/env bash
# File    : test.sh
# Brief   : Simple script to test the Samba server.
# Author  : Martin Rizzo | <martinrizzo@gmail.com>
# Date    : Jun 6, 2024
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
HELP="
Usage: $0 user:password[@host]

Test the Samba server by checking port connectivity and attempting a connection.

Parameters:
  user:password[@host]
      Specify the username, password, and optionally the host to test.
      If the host is not provided, the script will use the default host.
      (you can use a single dash '-' to run the script with default test values)

The script performs the following actions:
  1. Checks if Samba-related ports on the specified host are open and accessible.
  2. Attempts to establish a Samba connection using the provided credentials.

Examples:
  $0 -
  $0 bob:password
  $0 john:doe@192.168.1.100
  $0 alice:secret@fileserver.local
"

# ANSI colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # no Color


#================================= HELPERS =================================#

# Print help
display_help() {
    echo "$HELP"
}

# Print the IPs of the local network interfaces
local_ip_addresses() {
    ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1
}


#======================== SAMBA CHECKING FUNCTIONS =========================#

# Function to check Samba ports
check_samba_ports() {
    local host=${1:-localhost}
    ports=(139 445 137 138)

    echo "  [$host]"
    for port in "${ports[@]}"; do
        if nc -z -w1 "$host" "$port" &>/dev/null; then
            echo -e "    - Port $port: ${GREEN}Active${NC}"
        else
            echo -e "    - Port $port: ${RED}Inactive${NC}"
        fi
    done
}

# Function to connect and list Samba resources
list_samba_resources() {
    local username=$1 password=$2 host=$3

    echo -ne "Attempting to connect to Samba on $host...\r"

    # use smbclient to list resources
    output=$(smbclient -L "$host" -U "$username%$password" 2>&1)

    if [ $? -eq 0 ]; then
        echo -e "\033[K[$host] Available resources for $username:"
        echo "$output" | grep -E "Disk|Printer"
    else
        echo "Failed to connect: $output"
    fi
    echo
}

#===========================================================================#
# ///////////////////////////////// MAIN ////////////////////////////////// #
#===========================================================================#

# check if there are any arguments
if [[ -z $1 ]]; then
    display_help
    exit 1
fi

# check if the argument is a dash "-"
if [[ $1 == "-" ]]; then
    USER_NAME=
    # shellcheck disable=2207
    HOST_LIST=( $(local_ip_addresses) )

# validate the "user:pass" format
elif [[ "$1" =~ ^[^:]+:[^@]+$ ]]; then
    IFS=':' read -r USER_NAME PASSWORD <<< "$1"
    # shellcheck disable=2207
    HOST_LIST=( $(local_ip_addresses) )

# validate the "user:pass@host" format
elif [[ "$1" =~ ^[^:]+:[^@]+@[^@]+$ ]]; then
    IFS=':@' read -r USER_NAME PASSWORD HOST <<< "$1"
    HOST_LIST=( "$HOST" )

# the parameter format does not seem to be correct, print help
else
    display_help
    exit 1
fi

# display the status of the ports bound to Samba
echo
echo "Checking Samba Service"
for host in "${HOST_LIST[@]}"; do
    check_samba_ports "$host"
done
echo

# display the available resources for USER_NAME:PASSWORD
if [[ -n "$USER_NAME" ]]; then
    list_samba_resources "$USER_NAME" "$PASSWORD" "${HOST_LIST[0]}"
else
    list_samba_resources 'alice' 'alice' "${HOST_LIST[0]}"
    list_samba_resources 'bob'   'bob'   "${HOST_LIST[0]}"
fi
