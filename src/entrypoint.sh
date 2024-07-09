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
AVAHI_CONF_FILE="$SAMBA_CONF_DIR/avahi.conf"
SAMBA_LOG_FILE="$LOG_DIR/samba.log"
PID_FILE="$RUN_DIR/samba.pid"


# FILES
TEMP_FILE=$(mktemp /tmp/tempfile.XXXXXX)

# DEFAULT CONFIGURATION
CFG_RESOURCE_LIST='Files|files|This resource contains files available to all users'
CFG_USER_LIST='guest||Files'
CFG_PUBLIC_RESOURCES=
CFG_SERVER_NAME=SMBTEST
CFG_AVAHI=false
CFG_NETBIOS=true


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

    global_resources_conf=$(print_global_resources_conf "$resource_list")
    print_template "content:$(cat "$template_file")"        \
        '{SERVER_NAME}'           "$CFG_SERVER_NAME"        \
        '{SAMBA_CONF_DIR}'        "$SAMBA_CONF_DIR"         \
        '{MAIN_USER_NAME}'        "$QSERVER_USER"           \
        '{MAIN_GROUP_NAME}'       "$QSERVER_GROUP"          \
        '{GUEST_USER}'            "$QSERVER_USER"           \
        '{GLOBAL_RESOURCES_CONF}' "$global_resources_conf"  \
        '{USER_RESOURCES_CONF}'   "include = $SAMBA_CONF_DIR/%U.conf"
}

# Prints resource configuration
#
# Usage:
#   print_resource_conf <template> <resource_name> <directory> <writeable> <comment> <public_resources>
#
# Parameters:
#   - template     : The template file used for printing the configuration.
#   - resource_name: The name of the resource.
#   - directory    : The directory path for the resource.
#   - writeable    : Indicates if the resource is writeable. Should be 'yes' or 'no'.
#   - comment      : A comment or description for the resource.
#   - public_resources: A list of public resources. Must start and end with a space.
#
# Example:
#   print_resource_conf 'resource.template' 'MyResource' 'my/dir' 'yes' 'My comment' ' PublicResource '
#
print_resource_conf() {
    local template=$1 resource_name=$2 directory=$3 writeable=$4 comment=$5 public_resources=$6
    local path public

    # $writeable can be 'yes' or 'no'
    [[ "$writeable" == 'yes' || "$writeable" == 'no' ]] || \
        fatal_error "print_resource_conf() requires writeable to be 'yes' or 'no'"

    # $public_resources must start and end with a space
    [[ "${public_resources:0:1}" == ' ' && "${public_resources: -1}" == ' ' ]] || \
        fatal_error "print_resource_conf() requires public_resources to start and end with spaces"

    path="$APPDATA/$directory"

    # if the resource name is included in $public_resources
    # then make the resource 'public'
    public='no'
    [[ "$public_resources" == *" $resource_name "* ]] && public='yes'

    print_template "$template" \
        '{RESOURCE_NAME}'  "$resource_name" \
        '{COMMENT}'        "$comment"       \
        '{PATH}'           "$path"          \
        '{WRITEABLE}'      "$writeable"     \
        '{PUBLIC}'         "$public"
}

# Prints the global resources configuration based on the provided resource list
#
# Usage:
#   print_global_resources_conf <resource_list>
#
# Parameters:
#   - resource_list: A list of resources in the format "name|dir|comment"
#
# Example:
#   print_global_resources_conf "$CFG_RESOURCE_LIST"
#
# Note: Stores resource information in 'resource-$resname.data' files
#       This information will later be used by 'print_user_conf()'
#
print_global_resources_conf() {
    local resource_list=$1
    local visible writeable

    echo "$resource_list" | \
    while IFS='|' read -r resname directory comment; do
        case "$resname" in
               '') continue ;;
             '-'*) visible='no'  ; writeable='no'  ; resname=${resname#-} ; resname=${resname#-} ;;
            'w:'*) visible='yes' ; writeable='yes' ; resname=${resname:2} ;;
            'r:'*) visible='yes' ; writeable='no'  ; resname=${resname:2} ;;
                *) visible='yes' ; writeable='no'  ;;
        esac
        echo "$directory|$comment" > "resource-$resname.data"
        if [[ "$visible" == 'yes' ]]; then
            print_resource_conf 'global_resource.template' \
                "$resname" "$directory" "$writeable" "$comment" "$CFG_PUBLIC_RESOURCES"
        fi
    done
}

# Prints the user custom configuration based on provided user resources list
#
# Usage:
#   print_user_conf <username> <resources>
#
# Parameters:
#   - username : The name of the user.
#   - resources: A space-separated list of user resources.
#
# Example:
#   print_user_conf "user1" "w:Files r:Music -Documents"
#
# Note: Requires resource information from 'resource-$resname.data' files
#       which were previously created with 'print_global_resources_conf()'
#
print_user_conf() {
    local username=$1 resources=$2
    local visible writeable

    for resname in $resources; do
        case "$resname" in
               '') continue ;;
             '-'*) visible='no'  ; writeable='no'  ; resname=${resname#-} ; resname=${resname#-} ;;
            'w:'*) visible='yes' ; writeable='yes' ; resname=${resname:2} ;;
            'r:'*) visible='yes' ; writeable='no'  ; resname=${resname:2} ;;
                *) visible='yes' ; writeable='no'  ;;
        esac
        IFS='|' read -r directory comment < "resource-$resname.data"
        print_resource_conf 'local_resource.template' \
            "$resname" "$directory" "$writeable" "$comment" "$CFG_PUBLIC_RESOURCES"
    done
    echo
}

#======================== CONTROLLING AVAHI SERVICE ========================#


launch_avahi() {
    print_template samba_avahi_service.template \
        '{SERVER_NAME}'  "$CFG_SERVER_NAME" \
        > "/etc/avahi/services/smb.service"

    print_template avahi_config.template \
        '{AVAHI_SERVER}'  "null" \
        > "$AVAHI_CONF_FILE"

    avahi-daemon --daemonize --file="$AVAHI_CONF_FILE"
    if avahi-daemon --check; then
        message "Avahi daemon launched"
    else
        fatal_error 'Imposible lanzar el avahi daemon'
    fi
}

kill_avahi() {
    avahi-daemon --kill
}

launch_netbios() {
    local config_file=$1
    nmbd --daemon --configfile="$config_file" --no-process-group
}

#======================== CONTROLLING SAMBA SERVER =========================#

start_samba() {
    local config_file=$1
    exec ionice -c 3 smbd \
        --configfile="$config_file" \
        --debuglevel=0 --debug-stdout --foreground --no-process-group </dev/null
}

#========================== READING CONFIGURATION ==========================#

# Starts the configuration reading, initializing the temporary variables used
begin_config() {

    # these temporary variables are used to overwrite the
    # CFG_RESOURCE_LIST/CFG_USER_LIST configuration variables at the end
    TMP_RESOURCE_LIST=
    TMP_USER_LIST=
}

# Processes each configuration variable, updating the bash CFG_* variables
process_config_var() {
    local varname=$1 value=$2
    local ERROR=1

    case $varname in
        RESOURCE)
            value=$(format_value "$value" name reldir txt) || return $ERROR
            TMP_RESOURCE_LIST="${TMP_RESOURCE_LIST}${value}$NEWLINE"
            ;;
        USER)
            value=$(format_value "$value" user pass txt) || return $ERROR
            TMP_USER_LIST="${TMP_USER_LIST}${value}$NEWLINE"
            ;;
        SERVER_NAME)
            CFG_SERVER_NAME=$(format_value "$value" txt) || return $ERROR
            ;;
        AVAHI)
            CFG_AVAHI=$(format_value "$value" bool) || return $ERROR
            ;;
        NETBIOS)
            CFG_NETBIOS=$(format_value "$value" bool) || return $ERROR
            ;;
        PUBLIC_RESOURCES)
            CFG_PUBLIC_RESOURCES="$(format_value "$value" txt)" || return $ERROR
            ;;
        PRINT_ERROR)
            echo "ERROR: $value"
            ;;
    esac
}

# Finalizes the configuration reading, adjusting the processed values
end_config() {

    # if any resource or user was configured, then overwrite
    # the default CFG_RESOURCE_LIST/CFG_USER_LIST configuration
    TMP_RESOURCE_LIST=$(trim "$TMP_RESOURCE_LIST")
    if [[ "$TMP_RESOURCE_LIST" ]]; then
        CFG_RESOURCE_LIST=$TMP_RESOURCE_LIST
    fi
    TMP_USER_LIST=$(trim "$TMP_USER_LIST")
    if [[ "$TMP_USER_LIST" ]]; then
        CFG_USER_LIST=$TMP_USER_LIST
    fi
    unset TMP_RESOURCE_LIST TMP_USER_LIST

    # CFG_PUBLIC_RESOURCES must always start and end with a space!
    CFG_PUBLIC_RESOURCES=" $CFG_PUBLIC_RESOURCES "
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
    message "Processing configuration file: $QSERVER_CONFIG_FILE"
    begin_config
    for_each_config_var_in "$QSERVER_CONFIG_FILE" process_config_var
    end_config
else
    message "No configuration file found ($QSERVER_CONFIG_FILE)"
    message "Usando la configuracion default"
fi


echo "-----------------------------"
echo "CFG_RESOURCE_LIST:"
echo "$CFG_RESOURCE_LIST"
echo "CFG_USER_LIST:"
echo "$CFG_USER_LIST"
echo "-----------------------------"

# creando configuracion principal de samba
# en la cual tambien se incluye la configuracion global de los recursos
message "Generando configuracion"
print_samba_conf "$CFG_RESOURCE_LIST" > "$SAMBA_CONF_FILE"

# creando configuracion para cada usuario
echo "$CFG_USER_LIST" | \
while IFS='|' read -r username password resources; do
    if [[ -n $username && $username != 'guest' ]]; then
        output_file="$SAMBA_CONF_DIR/$username.conf"
        add_samba_vuser "$username" "$password"
        print_user_conf "$username" "$resources" > "$output_file"
    fi
done


remove_all_resconf_files


#
#message "Creating vsftpd configuration file: $VSFTPD_CONF_FILE"
#create_vsftpd_conf "$VSFTPD_CONF_FILE"
#
#message "Creating Linux users"
#create_qftp_users "$CFG_USER_LIST" "$CFG_RESOURCE_LIST"

if [[ "$CFG_AVAHI" == true ]]; then
    message "Launching Avahi service"
    launch_avahi
fi

if [[ "$CFG_NETBIOS" == true ]]; then
    message "Launching NetBIOS service"
    launch_netbios "$SAMBA_CONF_FILE"
fi

message "Starting SAMBA service"
start_samba "$SAMBA_CONF_FILE"



## hack
#chown $USER_NAME:$GROUP_NAME "$VSFTPD_LOG_FILE"
#chown $USER_NAME:$GORUP_NAME "$QFTP_LOG_FILE"
