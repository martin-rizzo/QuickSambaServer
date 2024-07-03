#!/bin/busybox sh
# File    : lib_utils.sh
# Brief   : A collection of utility functions for various tasks.
# Author  : Martin Rizzo | <martinrizzo@gmail.com>
# Date    : Apr 1, 2024
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


# Validates if a string represents an integer number.
function validate_integer() {
  [[ $1 =~ ^[0-9]+$ ]]
}

function run_as_user() {
    local command=$1
    if [ "$(id -u)" = "0" ]; then
        su -s /bin/sh -pc "$command" - $USER_NAME
    else
        eval "$command"
    fi
}

# Check if a file (or directory) is writable by a specified user.
#
# Usage:
#   is_writable <filepath> <user>
#
# Parameters:
#   - filepath : The path to the file to be checked for write permission.
#   - user     : The user whose write permission needs to be checked.
#
# Example:
#   is_writable "/path/to/file.txt" "bob"
#
function is_writable() {
    local filepath=$1 user=$2
    su "$user" -s /bin/sh -c "test -w \"$filepath\""
}

# Replace placeholders in a template with corresponding values.
#
# Usage:
#   print_template <template> [var1] [value1] [var2] [value2] ...
#   print_template <template> "${template_vars[@]}"
#
# Parameters:
#   - template          : Either a file path containing the template (File mode)
#                         or a string prefixed with 'content:' (Content mode)
#   - var1, value1, ... : Pairs of variables and values to replace in the template
#   - template_vars     : An array containing pairs of variables and values
#
# Example:
#
#   # File mode
#   template_vars=( "{NAME}" "John" "{DAY}" "Monday" )
#   print_template "path/to/my_template.txt" "${template_vars[@]}"
#
#   # Content mode
#   template_vars=( "{NAME}" "John" "{DAY}" "Monday" )
#   print_template "content:Hello, {NAME}! Today is {DAY}" "${template_vars[@]}"
#
function print_template() {
    local template=$1 ; shift

    # if the template starts with 'content:', treat it as a string.
    # Otherwise, treat it as a filename and read its content.
    if [[ "$template" == content:* ]]; then
        template=${template#content:}
    elif [[ -f "$template" ]]; then
        template=$(cat "$template")
    else
        fatal_error "Template file '${template:0:64}' not found"
    fi

    # replace placeholders with their corresponding values
    while [[ $# -gt 0 ]]; do
        local key=$1 value=$2
        template=${template//$key/$value}
        shift 2
    done
    echo "$template"
}

# Add a new Linux user account within the docker container.
#
# Usage:
#   add_system_user <user_name> <group_name> <home_dir> <tag>
#
# Parameters:
#   - user_name  : The desired username for the new user. If it contains a
#                  colon followed by a numerical value, it will be the numerical
#                  user ID; otherwise, the user ID will be automatically assigned.
#   - group_name : The name of the group to which the user will belong.
#   - home_dir   : The path to the user's home directory.
#   - tag        : A description or tag for the user.
#
# Example:
#   add_system_user "john_doe:1001" "developers" "/home/john_doe" __dev_tag__
#
add_system_user() {
    local user_name=$1 group_name=$2 home_dir=$3 tag=$4
    local user_id

    # separate the username from the numeric ID (if one is provided)
    case "$user_name" in
        *':'*)
            user_id=$(echo "$user_name" | cut -d ':' -f 2)
            user_name=$(echo "$user_name" | cut -d ':' -f 1)
            ;;
    esac

    # check if the username already exists in the system (must be unique)
    id "$user_name" &>/dev/null && \
        fatal_error "Unable to create user '$user_name', as that name is already in use by the system" \
                    "Please choose a different name"

    # add the new user to the system with the specified options
    if [[ -n "$user_id" ]]; then
        adduser "$user_name" -D -H -G "$group_name" -h "$home_dir" -g "$tag" -s /sbin/nologin --uid "$user_id"
    else
        adduser "$user_name" -D -H -G "$group_name" -h "$home_dir" -g "$tag" -s /sbin/nologin
    fi
}

# Check if a Linux user account exists within the docker container.
#
# Usage:
#   user_exists <user_name>
#
# Parameters:
#   - user_name  : The username to check for existence in the system.
#
# Example:
#   if user_exists "john_doe"; then
#       echo "User john_doe exists"
#   fi
#
user_exists() {
    local user_name=$1
    [[ -z "$user_name" ]] && fatal_error "user_exists() requires a parameter with a user name"
    id "$user_name" &>/dev/null
}

# Halts the execution of the script indefinitely.
#
# Notes:
#   This function suspends the execution of the script indefinitely.
#   It can be useful for testing or debugging purposes, as it allows you
#   to leave the script in a controlled state for further investigation.
#   It can be terminated by pressing Ctrl+C.
#
function halt() {
    echo "The script is running. Press Ctrl+C to stop it."
    while : ; do
        sleep 1
    done
}

# Checks if the current user is the root user.
#
# Notes:
#   This function checks if the ID of the current user is 0.
#   This can be useful for code that require elevated privileges to run.
#
function is_root() {
    [[ "$(id -u)" -eq 0 ]]
}
