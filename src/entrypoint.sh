#!/bin/busybox sh
# File    : entrypoint.sh
# Brief   : Entry point script for QuickSambaServer
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
# variables configurables:
#  - USER_ID
#  - GROUP_ID
#  - LOG_DIR
#
QSERVER_USER_ID=${USER_ID:-$(id -u)}
QSERVER_GROUP_ID="${GROUP_ID:-$(id -g)}"
QSERVER_LOG_DIR="${LOG_DIR:-log}"
unset USER_ID GROUP_ID LOG_DIR

# CONSTANTS
PROJECT_NAME=QuickSambaServer         # qss
CONFIG_NAME=samba.config              # qss config file
QSERVER_USER=qserver                  # qss main user & group
QSERVER_VUSER_TAG=__QSERVER_VUSER__   # qss virtual user tag
SCRIPT_DIR=$(dirname "$0")

APP=$SCRIPT_DIR
APPDATA=/appdata
RUN_DIR=/run




# QSERVER FILES & DIRS
QSERVER_CONFIG_FILE="$APPDATA/$CONFIG_NAME"
QSERVER_LOG_DIR="$APPDATA/$QSERVER_LOG_DIR"
QSERVER_LOG_FILE="$QSERVER_LOG_DIR/quicksambaserver.log"

# SAMBA FILES & DIRS
SAMBA_CONF_DIR="$APP/etc"
SAMBA_CONF_FILE="$SAMBA_CONF_DIR/smb.conf"
SAMBA_LOG_FILE="$LOG_DIR/samba.log"
PID_FILE="$RUN_DIR/samba.pid"


# FILES
TEMP_FILE=$(mktemp /tmp/tempfile.XXXXXX)

# CONFIG VARS
CFG_USER_LIST=
CFG_RESOURCE_LIST=



#================================== USERS ==================================#

# Ensure the existence of the main qserver user and group.
#
# Usage:
#   ensure_qserver_user_and_group
#
# Description:
#   If the QSERVER_USER_ID and QSERVER_GROUP_ID do not exist,
#   it creates them using the provided IDs and names.
#
# Output Globals:
#   QSERVER_USER  : The name of the main quickserver user.
#   QSERVER_GROUP : The name of the main quickserver group.
#
ensure_qserver_user_and_group() {
    local user_name=$1 user_id=$2 group_name=$3 group_id=$4
    message '{'

    # create 'group_id' if it don't exist
    if ! getent group $group_id $>/dev/null; then
        message "creating system group : $group_name [$group_id]"
        addgroup "$group_name" -g $group_id
    else
        group_name=$(getent group $group_id | cut -d: -f1)
    fi
    QSERVER_GROUP=$group_name

    # create 'user_id' if it don't exist
    if ! getent passwd "$user_id" &>/dev/null; then
        message "creating system user  : $user_name [$user_id]"
        add_system_user "$user_name:$user_id" "$group_name" '/home' "$PROJECT_NAME"
    else
        user_name=$(getent passwd $user_id | cut -d: -f1)
    fi
    QSERVER_USER=$user_name
    message '}'
}

# Adds a Samba virtual user with the specified username and password
#
# Usage:
#   add_samba_vuser <username> <password>
#
# Parameters:
#   - username: the username for the Samba virtual user
#   - password: the password for the Samba virtual user
#
# Example:
#   add_samba_vuser "user1" "password123"
#
add_samba_vuser() {
    local username=$1 password=$2

    # register user in the system (only if user do not already exist)
    if ! user_exists "$username"; then
        echo "$username:x:$QSERVER_USER_ID:$QSERVER_GROUP_ID:$QSERVER_VUSER_TAG:/home:/sbin/nologin" >> /etc/passwd
    else
        fatal_error "The user $username already exists in the system"
    fi

    # register user in Samba
    echo -e "$password\n$password" | smbpasswd -a -c "$SAMBA_CONF_FILE" -s "$username"
    echo "Samba virtual user created: $username"
}

# Removes all users previously created with 'add_samba_vuser()'
#
remove_all_samba_vusers() {

    # remove all users from the Samba registry
    # shellcheck disable=2034
    pdbedit --configfile="$SAMBA_CONF_FILE" --list | \
    while IFS=':' read -r username more; do
        echo "Removing Samba user $username"
        pdbedit --configfile="$SAMBA_CONF_FILE" --delete --user="$username"
    done

    # remove virtual users from the system
    sed -i "/$QSERVER_VUSER_TAG/d" /etc/passwd
}

#==================== RESOURCE CONFIGURATION FILE PATHS ====================#

# Generates the full path for a temporary resource configuration file
#
# Usage:
#   make_resconf_path <resource_name> [mode]
#
# Parameters:
#   - resource_name: the name of the resource, e.g., "Files", "Music"
#   - mode         : (optional) can be 'ro', 'rw', or 'def' (read-only, writable, and default)
#                    Defaults to 'def' if not provided.
# Example:
#   files_conf_path=$(make_resconf_path "Files" "rw")
#
make_resconf_path() {
    local resource_name=$1 mode=${2:-'def'}
    echo "$SAMBA_CONF_DIR/$resource_name-$mode.resconf"
}

# Removes all temporary resource configuration files created by 'make_resconf_path()'
#
remove_all_resconf_files() {
    rm -f "$SAMBA_CONF_DIR"/*.resconf
}


#====================== BUILDING SAMBA CONFIGURATION =======================#

# Prints the complete samba configuration
#
# Usage:
#   print_samba_conf <resource_list> [template_file]
#
# Parameters:
#   - resource_list: a list of resources in the format "name|dir|comment"
#   - template_file: (optional) the file used as a template.
#                    Defaults to 'samba_conf.template' if not provided.
#
# Example:
#   print_samba_conf "$CFG_RESOURCE_LIST" > "/app/etc/samba.conf"
#
print_samba_conf() {
    local resource_list=$1 template_file=${2:-'samba_config.template'}
    [[ ! -f "$template_file" ]] && fatal_error "print_samba_conf() requires the file $template_file"

    guest_resources=$(print_guest_resources "$resource_list")
    print_template "content:$(cat "$template_file")"  \
        '{SAMBA_CONF_FILE}'   "$SAMBA_CONF_DIR"       \
        '{MAIN_USER_NAME}'    "$QSERVER_USER"         \
        '{MAIN_GROUP_NAME}'   "$QSERVER_GROUP"        \
        '{GUEST_RESOURCES}'   "$guest_resources"      \
        '{GUEST_USER}'        "anonymous"
}

# Prints guest resource configurations based on the provided resource list
#
# Usage:
#   print_guest_resources <resource_list>
#
# Parameters:
#   - resource_list: a list of resources in the format "name|dir|comment"
#
# Example
#   print_guest_resources "$CFG_RESOURCE_LIST"
#
print_guest_resources() {
    local resource_list=$1

    echo "$resource_list" | \
    while IFS='|' read -r name directory comment; do
        if [[ $name ]]; then
            print_template samba_resource_guest.template \
                "{RESOURCE_NAME}"    "$name"             \
                "{RESOURCE_PATH}"    "$directory"        \
                "{RESOURCE_COMMENT}" "$comment"
        fi
    done
}

# Prints resource configuration based on name, directory, and comment
#
# Usage:
#   print_resource_conf <name> <directory> <comment>
#
# Parameters:
#   - name     : the name of the resource
#   - directory: the directory of the resource
#   - comment  : a comment describing the resource
#
# Example:
#   print_resource_conf "Documents" "docs" "User documents"
#
print_resource_conf() {
    local name=$1 directory=$2 comment=$3
    path="$APPDATA/$directory"

    message "Building resource $name"
    print_template "content:$(cat 'samba_resource.template')" \
        "{RESOURCE_NAME}"    "$name"     \
        "{RESOURCE_PATH}"    "$path"     \
        "{RESOURCE_COMMENT}" "$comment"
}

# Prints user configuration based on username, password, and resources
#
# Usage:
#   print_user_conf <username> <password> <resources>
#
# Parameters:
#   - username : the username of the user
#   - password : the password of the user
#   - resources: a comma-separated list of resource names
#
# Example:
#   print_user_conf "user1" "password123" "Files,Music"
#
print_user_conf() {
    local username=$1 password=$2 resources=$3

    for name in ${resources//,/ } ; do
        resource_conf_file=$(make_resconf_path "$name")
        cat "$resource_conf_file"
    done
    echo
}

#======================== CONTROLLING SAMBA SERVER =========================#

start_samba() {
    exec ionice -c 3 smbd \
        --configfile="$SAMBA_CONF_FILE" \
        --debuglevel=0 --debug-stdout --foreground --no-process-group </dev/null
}

#========================== READING CONFIGURATION ==========================#

process_config_var() {
    local varname=$1 value=$2
    local ERROR=1

    case $varname in
        RESOURCE)
            value=$(format_value "$value" name reldir txt) || return $ERROR
            CFG_RESOURCE_LIST="${CFG_RESOURCE_LIST}${value}$NEWLINE"
            ;;
        USER)
            value=$(format_value "$value" user pass reslist) || return $ERROR
            CFG_USER_LIST="${CFG_USER_LIST}${value}$NEWLINE"
            ;;
        PRINT_ERROR)
            echo "ERROR: $value"
            ;;
    esac
}

#===========================================================================#
# ///////////////////////////////// MAIN ////////////////////////////////// #
#===========================================================================#

# load modules
source "$SCRIPT_DIR/lib_config.sh"  # functions for reading config files
source "$SCRIPT_DIR/lib_logfile.sh" # functions for handling logging messages
source "$SCRIPT_DIR/lib_utils.sh"   # miscellaneous utility functions

echo -e '\n-----------------------------------------------------------'
echo -e "$BLUE$0"

message "Validating USER_ID"  # QSERVER_USER_ID
if ! validate_integer "$QSERVER_USER_ID" ; then
    fatal_error "USER_ID must be a valid integer value"
fi

message "Validating GROUP_ID" # QSERVER_GORUP_ID
if ! validate_integer "$QSERVER_GROUP_ID" ; then
    fatal_error "GROUP_ID must be a valid integer value"
fi

if is_root; then
    message "Ensuring existence of main user/group [$QSERVER_USER_ID/$QSERVER_GROUP_ID]"
    ensure_qserver_user_and_group           \
        "$QSERVER_USER" "$QSERVER_USER_ID"  \
        "$QSERVER_USER" "$QSERVER_GROUP_ID"
fi

message "Activating the log file for this script: $QSERVER_LOG_FILE"
set_logfile "$QSERVER_LOG_FILE"

message "Switching to the app's directory: $APP"
cd "$APP" \
 || fatal_error "Failed to change directory to $APP"

#message "Removing any previous samba configurations"
#rm -f "$SAMBA_CONF_DIR/*"
#rm -f "/$VIRTUAL_USERS_DIR/*"
#remove_all_samba_vusers

if [[ -f "$QSERVER_CONFIG_FILE" ]]; then
    message "Reading configuration file: $QSERVER_CONFIG_FILE"
    for_each_config_var_in "$QSERVER_CONFIG_FILE" process_config_var
else
    message "No configuration file found ($QSERVER_CONFIG_FILE)"
    message "Usando la configuracion default"
fi

# si no hubo declaracion de recursos entonces asignar la declaracion default
CFG_RESOURCE_LIST=$(trim "$CFG_RESOURCE_LIST")
if [[ -z $CFG_RESOURCE_LIST ]]; then
    CFG_RESOURCE_LIST='Files|files|This resource contains files available to all users'
fi

# si no hubo declaracion de usuarios entonces asignar la declaracion default
CFG_USER_LIST=$(trim "$CFG_USER_LIST")
if [[ -z $CFG_USER_LIST ]]; then
    CFG_USER_LIST='guest||Files'
fi

echo "-----------------------------"
echo "CFG_RESOURCE_LIST:"
echo "$CFG_RESOURCE_LIST"
echo "CFG_USER_LIST:"
echo "$CFG_USER_LIST"
echo "-----------------------------"

# creando configuracion principal de samba
message "Generando configuracion"
print_samba_conf "$CFG_RESOURCE_LIST" > "$SAMBA_CONF_FILE"

# creando configuracion para cada recurso declarado
echo "$CFG_RESOURCE_LIST" | \
while IFS='|' read -r name directory comment; do
    if [[ $name ]]; then
        resource_conf_file=$(make_resconf_path "$name")
        print_resource_conf "$name" "$directory" "$comment" > "$resource_conf_file"
    fi
done

# creando configuracion para cada usuario
echo "$CFG_USER_LIST" | \
while IFS='|' read -r username password resources; do
    if [[ $username ]]; then
        output_file="$SAMBA_CONF_DIR/$username.conf"
        [[ $username == 'guest' ]] && username='anonymous'
        add_samba_vuser "$username" "$password"
        print_user_conf "$username" "$password" "$resources" > "$output_file"
    fi
done

remove_all_resconf_files


#
#message "Creating vsftpd configuration file: $VSFTPD_CONF_FILE"
#create_vsftpd_conf "$VSFTPD_CONF_FILE"
#
#message "Creating Linux users"
#create_qftp_users "$CFG_USER_LIST" "$CFG_RESOURCE_LIST"


message "Starting SAMBA service"
start_samba "$SAMBA_CONF_FILE"



## hack
#chown $USER_NAME:$GROUP_NAME "$VSFTPD_LOG_FILE"
#chown $USER_NAME:$GORUP_NAME "$QFTP_LOG_FILE"
