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

# Add a Samba virtual user
#
# Usage:
#   add_samba_vuser <username> <password>
#
# Description:
#   This function adds a new Samba virtual user.
#   If the user already exists, an error message is displayed and the script exits.
#
# Example:
#   add_samba_vuser user1 password123
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

# Remove all Samba virtual users
#
# Usage:
#   remove_all_samba_vusers
#
# Description:
#   This function removes all users previously created with 'add_samba_vuser()'
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


# # Create virtual FTP users and associate them with specified resources.
# #
# # Usage:
# #   create_virtual_user <user_name> <user_pass> <user_resources> <resource_list> [options]
# #
# # Parameters:
# #   - user_name      : Username for the virtual FTP user.
# #   - user_pass      : Password for the virtual FTP user.
# #   - user_resources : Comma-separated list of resources to associate with the user.
# #   - resource_list  : List of available resources. Each line should be formatted as
# #                      "resname|resdir|text"
# #   - options        : Comma-separated list of options for additional configurations.
# #
# # Globals:
# #   DIRS_TO_VERIFY : Directories of the created virtual user are appended to
# #                    this list to verify them during post-processing.
# # Example:
# #   create_virtual_user "john" "pass123" "res1,res2" "$RESOURCE_LIST" sys_user,writable_is_fatal
# #
# # Notes:
# #   - If 'sys_user' option is provided, the script will create a system user with
# #     the given username and password.
# #   - If 'writable_is_fatal' option is provided, any attempt to create a virtual
# #     userwith a writable home directory will result in a fatal error.
# #   - Every resource listed in 'user_resources' must exist in the 'resource_list'.
# #   - Each virtual user can only be associated with one resource. If a user is
# #     assigned multiple resources, an error will be generated.
# #
# function create_virtual_user() {
#     local user_name=$1 user_pass=$2 user_resources=$3 resource_list=$4 options=$5
#     local chpasswd_message resource_values resdir home_dir writable_is_fatal
#
#     # loop a travez de las opciones suministradas
#     IFS=',' ; for opt in $options; do
#         case $opt in
#
#             # sys_user -> create user and set password
#             sys_user)
#                 add_system_user "$user_name" "$GROUP_NAME" '/home' "$QFTP_USER_TAG"
#                 chpasswd_message=$(echo "$user_name:$user_pass" | chpasswd 2>&1)
#                 echo "      - $chpasswd_message"
#                 ;;
#
#             # writable_is_fatal -> fatal error if the home directory is writable
#             writable_is_fatal)
#                 writable_is_fatal=true
#                 ;;
#
#         esac
#     done
#
#     # loop through user resources.
#     IFS=',' ; for resource in $user_resources; do
#
#         # get resource info
#         resource_values=$(find_config_values "$resource" "$resource_list")
#         [[ -z "$resource_values" ]] && \
#             fatal_error "Resource '$resource' was not defined" \
#                         "Please review the $CONFIG_NAME file"
#         resdir=$(echo "$resource_values" | cut -d '|' -f 2)
#         [[ -z "$resdir" ]] && \
#             fatal_error "Resource '$resource' does not have an associated directory" \
#                         "Please review the $CONFIG_NAME file"
#
#         # define the home directory for the user based on the resource directory
#         home_dir="$APPDATA_DIR/$resdir"
#         [[ ! -d "$home_dir" ]] && \
#             fatal_error "Directory '$resdir' associated with resource '$resource' does not exist." \
#                         "Please review the $CONFIG_NAME file."
#
#         [[ -e "/$VIRTUAL_USERS_DIR/$user_name" ]] && \
#             fatal_error "El usuario '$user_name' tiene mas de un recurso asignado" \
#                         "Please review the $CONFIG_NAME file."
#
#         # link the user's home directory
#         ln -s "$home_dir" "/$VIRTUAL_USERS_DIR/$user_name"
#
#         # add the directory to the list
#         # (if 'writable_is_fatal' then prefix it with '!')
#         [[ "$writable_is_fatal" == true ]] && home_dir="!${home_dir}"
#         DIRS_TO_VERIFY="${DIRS_TO_VERIFY}:${home_dir}"
#
#     done
# }


# # Create QuickFtpServer users based on the provided user list.
# # (users are created as system users to be read by vsftpd via PAM)
# #
# # Usage:
# #   create_qftp_users <user_list> <resource_list>
# #
# # Parameters:
# #   - user_list     : List of users to be created. Each line should be formatted as
# #                     "username|password|resource"
# #   - resource_list : List of available resources. Each line should be formatted as
# #                     "resname|resdir|text".
# # Example:
# #   create_qftp_users "$CFG_USER_LIST" "$CFG_RESOURCE_LIST"
# #
# # Notes:
# #   - If a user already exists in the system, an error will be generated.
# #   - All created users can be removed with the function remove_all_qftp_users.
# #
# function create_qftp_users() {
#     local user_list=$1 resource_list=$2
#
#     DIRS_TO_VERIFY=
#
#     # iterate over each line of the user list
#     echo "$user_list" > $TEMP_FILE
#     while IFS='|' read -r user_name user_pass user_resources;
#     do
#
#         # skip if the username is empty
#         [[ -z "$user_name" ]] && continue
#
#         # create the virtual user and associate it with its resources
#         # (the 'ftp' user is the anonymous user and doesn't need a system user)
#         if [[ "$user_name" == ftp ]]; then
#             create_virtual_user "$user_name" "$user_pass" "$user_resources" "$resource_list" writable_is_fatal
#         else
#             create_virtual_user "$user_name" "$user_pass" "$user_resources" "$resource_list" sys_user
#         fi
#
#     done < $TEMP_FILE
#     rm $TEMP_FILE
#
#     verify_read_only_directories "$DIRS_TO_VERIFY" "$MAIN_USER" "$CFG_FIX_WRITABLE_ROOT"
#
# }

#====================== BUILDING SAMBA CONFIGURATION =======================#

# Create the samba configuration file from the template.
#
# create_vsftpd_conf <output_file> [template_file]
#
# Parameters:
#   - output_file: the path to the samba configuration file to be created.
#   - template_file: (opcional) el archivo utilizado como template
#
# Example: build_samba_conf "/app/tmp/samba.conf"
#
build_samba_conf() {
    local output_file=$1 template_file=${2:-'samba_config.template'}
    [[ -z   "$output_file"   ]] && fatal_error "build_samba_conf() requires a parameter with the output file"
    [[ ! -f "$template_file" ]] && fatal_error "build_samba_conf() requires the file $PWD/$template_file"

    print_template "$(cat "$template_file")"    \
        "{SAMBA_CONF_FILE}"   "$SAMBA_CONF_DIR" \
        "{MAIN_USER_NAME}"    "$USER_NAME"      \
        "{MAIN_GROUP_NAME}"   "$GROUP_NAME"     \
        > "$output_file"
}

build_resource_conf() {
    local name=$1 directory=$2 comment=$3
    local path output_file
    path="$APPDATA/$directory"

    echo "Building resource $name"
    output_file="$SAMBA_CONF_DIR/resource-$name.conf"
    print_template "$(cat 'samba_resource.template')" \
        "{RESOURCE_NAME}"    "$name"     \
        "{RESOURCE_PATH}"    "$path"     \
        "{RESOURCE_COMMENT}" "$comment"  \
        > "$output_file"
}

build_user_conf() {
    local username=$1 password=$2 resources=$3

    add_samba_vuser "$username" "$password"

    output_file="$SAMBA_CONF_DIR/$username.conf"
    rm -f "$output_file"
    for name in ${resources//,/ } ; do
        cat "$SAMBA_CONF_DIR/resource-$name.conf" >> "$output_file"
    done
    echo >> "$output_file"
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

start_samba() {
    exec ionice -c 3 smbd \
        --configfile="$SAMBA_CONF_FILE" \
        --debuglevel=0 --debug-stdout --foreground --no-process-group </dev/null
}

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
#remove_all_qserver_users

message "Reading configuration file: $QSERVER_CONFIG_FILE"
for_each_config_var_in "$QSERVER_CONFIG_FILE" process_config_var

echo "-----------------------------"
echo "CFG_RESOURCE_LIST:"
echo "$CFG_RESOURCE_LIST"
echo "CFG_USER_LIST:"
echo "$CFG_USER_LIST"
echo "-----------------------------"

# creando configuracion principal de samba
message "Generando configuracion"
build_samba_conf "$SAMBA_CONF_FILE"


# creando configuracion para cada recurso
echo "$CFG_RESOURCE_LIST" | \
while IFS='|' read -r name directory comment; do
    [[ $name ]] && build_resource_conf "$name" "$directory" "$comment"
done

# creando configuracion para cada usuario
echo "$CFG_USER_LIST" | \
while IFS='|' read -r username password resources; do
    [[ $username ]] && build_user_conf "$username" "$password" "$resources"
done



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
