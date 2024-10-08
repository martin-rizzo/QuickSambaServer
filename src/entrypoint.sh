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

# INPUT: USER_ID, GROUP_ID
QSERVER_USER=                            # qss main user
QSERVER_GROUP=                           # qss main group
QSERVER_USER_ID=                         # qss main user-id
QSERVER_GROUP_ID=                        # qss main group-id

# CONSTANTS
PROJECT_NAME=QuickSambaServer            # qss
CONFIG_NAME=qsamba                       # qss config name (.config/.ini)
QSERVER_DEFAULT_USER=qserver             # qss default user name
QSERVER_DEFAULT_GROUP=qserver            # qss default group name
QSERVER_VUSER_TAG=__QSERVER_VUSER__      # qss virtual user tag
SCRIPT_DIR=$(dirname "$0")

# MAIN DIRS
APP=$SCRIPT_DIR
APPDATA=/appdata

# QSERVER FILES & DIRS
QSERVER_CONFIG_EXT= # will be automatically determined by the script
QSERVER_CONFIG_FILE="$APPDATA/$CONFIG_NAME"
QSERVER_LOG_DIR=/var/log/samba
QSERVER_LOG_FILE="$QSERVER_LOG_DIR/quicksambaserver.log"

# SAMBA FILES & DIRS
SAMBA_CONF_DIR="$APP/etc"
SAMBA_CONF_FILE="$SAMBA_CONF_DIR/smb.conf"
AVAHI_CONF_FILE="$SAMBA_CONF_DIR/avahi.conf"

# DEFAULT CONFIGURATION
CFG_RESOURCE_LIST='Files|files|This resource contains files available to all users'
CFG_USER_LIST='guest||Files'
CFG_PUBLIC_RESOURCES='  '
CFG_SERVER_NAME=SMBTEST
CFG_AVAHI=false
CFG_NETBIOS=true
CFG_USER_ID=
CFG_GROUP_ID=
CFG_NEW_DIR_MODE=
CFG_NEW_FILE_MODE=


#============================ MAIN SYSTEM USERS ============================#

# Adds a system group with the specified group ID
#
# Usage: add_qserver_group <group_id>
#
# Parameters:
#   - group_id: the ID for the system group
#
# Note:
#   Returns the name of the group that was added via stdout.
#   This can be captured using command substitution `$(..)`.
#
# Example:
#   QSERVER_GROUP=$(add_qserver_group 1000) || exit 1
#
add_qserver_group() {
    local group_id=$1

    # if the system already has 'group_id' defined
    # then return the name of that group in stdout
    if  getent group "$group_id" &>/dev/null; then
        getent group "$group_id" | cut -d: -f1
        return
    fi

    # create 'group_id' using the default name
    message "creating system group : $QSERVER_DEFAULT_GROUP [$group_id]"
    addgroup "$QSERVER_DEFAULT_GROUP" -g "$group_id"
    echo "$QSERVER_DEFAULT_GROUP"
}

# Adds a system user with the specified user ID and group name
#
# Usage: add_qserver_user <user_id> <group_name>
#
# Parameters:
#   - user_id   : the ID for the system user
#   - group_name: the name of the group to which the user belongs
#
# Note:
#   Returns the name of the user that was added via stdout.
#   This can be captured using command substitution `$(..)`.
#
# Example:
#   QSERVER_USER=$(add_qserver_user 1001 "qserver_group") || exit 1
#
add_qserver_user() {
    local user_id=$1 group_name=$2

    # if the system already has 'user_id' defined
    # then return the name of that user in stdout
    if  getent passwd "$user_id" &>/dev/null; then
        getent passwd "$user_id" | cut -d: -f1
        return
    fi

    # create 'user_id' using the default name
    message "creating system user  : $QSERVER_DEFAULT_USER [$user_id]"
    add_system_user "$QSERVER_DEFAULT_USER:$user_id" "$group_name" '/home' "$PROJECT_NAME"
    echo "$QSERVER_DEFAULT_USER"
}

# Removes previously created qserver user and group.
#
remove_qserver_user_and_group() {
    groupdel   "$QSERVER_DEFAULT_GROUP" &>/dev/null
    userdel -r "$QSERVER_DEFAULT_USER"  &>/dev/null
}


#============================== VIRTUAL USERS ==============================#

# Adds a Samba virtual user with the specified username and password
#
# Usage: add_samba_vuser <username> <password>
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
        internal_error "The user $username already exists in the system"
    fi

    # register user in Samba
    echo -e "$password\n$password" | smbpasswd -a -c "$SAMBA_CONF_FILE" -s "$username" 1>/dev/null
    message "Samba virtual user created: $username"
}

# Removes all users previously created with 'add_samba_vuser()'
#
# Usage: remove_all_samba_vusers <config_file>
#
# Example:
#   remove_all_samba_vusers "$SAMBA_CONF_FILE"
#
remove_all_samba_vusers() {
    local config_file=$1

    # if the configuration file does not exist, return without doing anything
    [[ ! -f "$config_file" ]] && return

    # remove all users from the Samba registry
    pdbedit --configfile="$config_file" --list | \
    while IFS=':' read -r username _; do
        echo "Removing Samba user $username"
        pdbedit --configfile="$config_file" --delete --user="$username"
    done

    # remove virtual users from the system
    sed -i "/$QSERVER_VUSER_TAG/d" /etc/passwd
}


#====================== BUILDING SAMBA CONFIGURATION =======================#

parse_resource() {
    local flag_resname=$1 flag resname
    case "$flag_resname" in
         '-'*) flag='-' ; resname=${flag_resname#-} ; resname=${resname#-} ;;
        'w:'*) flag='w' ; resname=${flag_resname:2} ;;
        'r:'*) flag='r' ; resname=${flag_resname:2} ;;
            *) flag=''  ; resname=${flag_resname}   ;;
    esac
    echo "$flag|$resname"
}

# Generates the resource data used by 'print_user_conf()/print_samba_conf()'
#
# Usage:  generate_resource_data <resdata_prefix> <resource_list>
#
# Parameters:
#   - resdata_prefix: Prefix used to store data for each resource
#   - resource_list : A list of resources in the format "name|dir|comment"
#
# Example:
#   generate_resource_data resdata "$CFG_RESOURCE_LIST"
#
generate_resource_data() {
    local resdata_prefix=$1 resource_list=$2

    rm -f "$SAMBA_CONF_DIR/$resdata_prefix".tmpdata
    echo "$resource_list" | \
    while IFS='|' read -r flag_resname directory comment; do
        IFS='|'   read -r flag resname < <(parse_resource "$flag_resname")
        [[ -z "$resname" || -z "$directory" ]] && continue
        echo "$flag|$resname|$directory|$comment" >  "$SAMBA_CONF_DIR/$resdata_prefix-$resname".tmpdata
        echo "$flag|$resname|$directory|$comment" >> "$SAMBA_CONF_DIR/$resdata_prefix".tmpdata
    done
}

# Prints the complete samba configuration
#
# Usage: print_samba_conf <resdata_prefix> [template_file]
#
# Parameters:
#   - resdata_prefix: Prefix used to store data for each resource, must be the
#                     same as the one provided to 'generate_resource_data()'
#   - template_file: (optional) the file used as a template.
#                    Defaults to 'samba_conf.template' if not provided.
#
# Example:
#   print_samba_conf resdata > "/app/etc/samba.conf"
#
print_samba_conf() {
    local resdata_prefix=$1 template_file=${2:-'samba_config.template'}
    [[ ! -f "$template_file" ]] && fatal_error "print_samba_conf() requires the file $template_file"

    # set default values for file and directory permission masks and force modes.
    local create_mask=0744
    local directory_mask=0755
    local force_create_mode=0000
    local force_directory_mode=0000

    # if the user has specified a custom permission mode for newly created directories,
    # update the directory mask and force mode variables
    if [[ -n "$CFG_NEW_DIR_MODE" ]]; then
        directory_mask=$CFG_NEW_DIR_MODE
        force_directory_mode=$CFG_NEW_DIR_MODE
    fi

    # if the user has specified a custom permission mode for newly created files,
    # update the file mask and force mode variables
    if [[ -n "$CFG_NEW_FILE_MODE" ]]; then
        create_mask=$CFG_NEW_FILE_MODE
        force_create_mode=$CFG_NEW_FILE_MODE
    fi

    # generate the configuration for global resources accessible to all users
    local global_resources_conf
    global_resources_conf=$(print_global_resources_conf "$resdata_prefix")

    # print the Samba configuration template,
    # replacing placeholders with actual values
    print_template "content:$(cat "$template_file")"        \
        '{SERVER_NAME}'           "$CFG_SERVER_NAME"        \
        '{SAMBA_CONF_DIR}'        "$SAMBA_CONF_DIR"         \
        '{MAIN_USER_NAME}'        "$QSERVER_USER"           \
        '{MAIN_GROUP_NAME}'       "$QSERVER_GROUP"          \
        '{GUEST_USER}'            "$QSERVER_USER"           \
        '{CREATE_MASK}'           "$create_mask"            \
        '{FORCE_CREATE_MODE}'     "$force_create_mode"      \
        '{DIRECTORY_MASK}'        "$directory_mask"         \
        '{FORCE_DIRECTORY_MODE}'  "$force_directory_mode"   \
        '{GLOBAL_RESOURCES_CONF}' "$global_resources_conf"  \
        '{USER_RESOURCES_CONF}'   "include = $SAMBA_CONF_DIR/%U.conf"
}

# Prints the global resources configuration based on the provided resdata
#
# Usage:  print_global_resources_conf <resdata_prefix>
#
# Parameters:
#   - resdata_prefix: Prefix used to store data for each resource
#
# Example:
#   print_global_resources_conf resdata
#
print_global_resources_conf() {
    local resdata_prefix=$1
    local visible writeable

    while IFS='|' read -r flag resname directory comment; do
        [[ -z "$resname" || -z "$directory" ]] && continue
        case "$flag" in
             '-') visible='no'  ; writeable='no'  ;;
             'w') visible='yes' ; writeable='yes' ;;
             'r') visible='yes' ; writeable='no'  ;;
               *) visible='yes' ; writeable='no'  ;;
        esac
        if [[ "$visible" == 'yes' ]]; then
            print_resource_conf 'resource_config.template' \
                "$resname" "$comment" "$directory" 'yes' "$writeable" '' "$CFG_PUBLIC_RESOURCES"
        fi
    done < "$SAMBA_CONF_DIR/$resdata_prefix".tmpdata
}

# Prints resource configuration
#
# Usage: print_resource_conf <template> <resource_name> <comment> <directory> <browseable> <writeable> <public_resources>
#
# Parameters:
#   - template     : The template file used for printing the configuration.
#   - resource_name: The name of the resource.
#   - comment      : A comment or description for the resource.
#   - directory    : The directory path for the resource.
#   - browseable   : Indicates whether the resource is visible in the client. Should be 'yes' or 'no'.
#   - writeable    : Indicates if the resource is writeable. Should be 'yes' or 'no'.
#   - extra_config : Any extra configuration that you want to add to the resource.
#   - public_resources: A list of public resources. Must start and end with a space.
#
# Example:
#   print_resource_conf 'resource.template' 'MyResource' 'My comment' '/home/user/shared' 'yes' 'no' 'invalid users = user1' ' PublicResource1 PublicResource2 '
#
print_resource_conf() {
    local template=$1 resource_name=$2 comment=$3 directory=$4 browseable=$5 writeable=$6
    local extra_config=$7 public_resources=$8
    local path

    # $writeable can be 'yes' or 'no'
    [[ "$writeable" == 'yes' || "$writeable" == 'no' ]] || \
        internal_error "print_resource_conf() requires \$writeable to be 'yes' or 'no'. You provided '$writeable' instead"

    # $browseable can be 'yes' or 'no'
    [[ "$browseable" == 'yes' || "$browseable" == 'no' ]] || \
        internal_error "print_resource_conf() requires \$browseable to be 'yes' or 'no'. You provided '$writeable' instead"

    # $public_resources must start and end with a space
    [[ "${public_resources:0:1}" == ' ' && "${public_resources: -1}" == ' ' ]] || \
        internal_error "print_resource_conf() requires public_resources to start and end with spaces"

    local path="$APPDATA/$directory"

    # if the resource name is included in $public_resources
    # then make the resource 'public'
    local public='no'
    [[ "$public_resources" == *" $resource_name "* ]] && public='yes'

    print_template "$template" \
        '{RESOURCE_NAME}'  "$resource_name" \
        '{COMMENT}'        "$comment"       \
        '{PATH}'           "$path"          \
        '{BROWSEABLE}'     "$browseable"    \
        '{PUBLIC}'         "$public"        \
        '{WRITEABLE}'      "$writeable"     \
        '{EXTRA_CONFIG}'   "$extra_config"
}

# Prints the user custom configuration based on provided user resources list
#
# Usage:  print_user_conf <username> <resources> <resdata_prefix>
#
# Parameters:
#   - username      : The name of the user.
#   - resources     : A space-separated list of user resources.
#   - resdata_prefix: Prefix used to store data for each resource, must be the
#                     same as the one provided to 'generate_resource_data()'
#
# Note:
#   Requires resource information from '$resdata_prefix-$resname.data' files
#   which were previously created with 'generate_resource_data()'
#
# Example:
#   print_user_conf "user1" "w:Files r:Music -Documents" resdata
#
print_user_conf() {
    local username=$1 resources=$2 resdata_prefix=$3

    for flag_resname in $resources; do

        IFS='|' read -r flag resname < <(parse_resource "$flag_resname")
        [[ -z "$resname" ]] && continue

        # gets the global resource configuration
        [[ ! -f "$SAMBA_CONF_DIR/$resdata_prefix-$resname".tmpdata ]] && continue
        IFS='|' read -r global_flag _ directory comment < "$SAMBA_CONF_DIR/$resdata_prefix-$resname".tmpdata

        # resolves the case where the user resource has no flag,
        # it will be read-only by default unless the global resource is 'w:'
        if [[ -z "$flag" ]]; then
            flag='r'
            [[ "$global_flag" = 'w' ]] && flag='w'
        fi

        local browseable='yes' writeable='no'
        case "$flag" in
            '-') browseable='no'  ; writeable='no'  ; extra="invalid users = $username" ;;
            'w') browseable='yes' ; writeable='yes' ; extra='' ;;
            'r') browseable='yes' ; writeable='no'  ; extra='' ;;
              *) internal_error "invalid resource flag '$flag' in print_user_conf()"  ;;
        esac
        print_resource_conf 'resource_config.template' \
            "$resname" "$comment" "$directory" "$browseable" "$writeable" "$extra" "  "
    done
    echo
}

# Removes the temporary data files created by 'generate_resource_data()'
#
# Usage:  remove_resource_data <resdata_prefix>
#
# Parameters:
#   - resdata_prefix: Prefix used to store data for each resource
#
# Example:
#   remove_resource_data resdata
#
remove_resource_data() {
    local resdata_prefix=$1
    rm -f "$SAMBA_CONF_DIR/$resdata_prefix"*.tmpdata
}


#========================== CONTROLLING SERVICES ===========================#

# Launches the Avahi daemon, automatically generating configuration files.
# This function sets up Avahi to advertise the Samba service on the network.
#
launch_avahi() {

    # generate the main Avahi config file
    print_template avahi_config.template \
        '{AVAHI_SERVER}'  "null" \
        > "$AVAHI_CONF_FILE"

    # generate the config file for advertising the Samba service via Avahi
    print_template samba_avahi_service.template \
        '{SERVER_NAME}'  "$CFG_SERVER_NAME" \
        > "/etc/avahi/services/smb.service"

    # launch the Avahi daemon in the background
    avahi-daemon --daemonize --file="$AVAHI_CONF_FILE"

    # give the Avahi daemon a moment to start
    # and check if it is running
    sleep 1
    if avahi-daemon --check; then
        message 'Avahi daemon launched'
    else
        fatal_error 'Impossible to launch the Avahi daemon'
    fi
}

# Stops the Avahi daemon
#
kill_avahi() {
    avahi-daemon --kill
}

# Launches the NetBIOS daemon with the specified configuration file
#
launch_netbios() {
    local config_file=$1

    # launch the NetBIOS daemon in the background
    nmbd --daemon --configfile="$config_file" --no-process-group

    # give the NetBIOS daemon a moment to start
    # and check if it is running
    sleep 1
    if pgrep -x "nmbd" > /dev/null; then
        message 'NetBIOS daemon launched'
    else
        fatal_error 'Impossible to launch the NetBIOS daemon'
    fi
}

# Stops the NetBIOS daemon
#
kill_netbios() {
    local pid

    # try to get the PID from the PID file
    pid=$(cat '/var/run/samba/nmbd.pid' 2>/dev/null)

    # if no PID from the file, try to find it using pgrep
    if [[ -z "$pid" ]] || ! ps -p "$pid" > /dev/null 2>&1; then
        pid=$(pgrep -x "nmbd")
    fi

    # if no PID found, the NetBIOS daemon is probably not running
    if [[ -z "$pid" ]]; then
        message "NetBIOS daemon is not running"
        return 0
    fi

    message "Stopping NetBIOS daemon (PID: $pid)"
    if kill -TERM "$pid"; then
        # wait for the process to stop
        for _ in {1..10}; do
            if ! ps -p "$pid" > /dev/null 2>&1; then
                message "NetBIOS daemon stopped successfully"
                return 0
            fi
            sleep 1
        done
        # if it's still running after 10 seconds, force kill
        echo 'NetBIOS daemon did not stop gracefully. Forcing termination...'
        kill -KILL "$pid"
    fi
}

# Starts the Samba daemon with the specified configuration file.
#
start_samba() {
    local config_file=$1
    exec ionice -c 3 smbd \
        --configfile="$config_file" \
        --debuglevel=0 --debug-stdout --foreground --no-process-group </dev/null
}


#========================== READING CONFIGURATION ==========================#

# Starts the configuration reading process and initializes temporary variables
begin_config_vars() {
    local config_file=$1

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
        USER_ID)
            CFG_USER_ID=$(format_value "$value" int) || return $ERROR
            ;;
        GROUP_ID)
            CFG_GROUP_ID=$(format_value "$value" int) || return $ERROR
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
        NEW_DIR_MODE)
            CFG_NEW_DIR_MODE="$(format_value "$value" mode)" || return $ERROR
            ;;
        NEW_FILE_MODE)
            CFG_NEW_FILE_MODE="$(format_value "$value" mode)" || return $ERROR
            ;;
        PRINT_ERROR)
            echo "ERROR: $value"
            ;;
    esac
}

# Finalizes the configuration reading, adjusting the processed values
end_config_vars() {

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


# before starting, perform several validations:
#   1) Validate that the script is being executed with a privileged user
#   +  Activate the log file
#   2) Validate that the /appdata volume is correctly mounted
#   3) Validate USER_ID
#   4) Validate GROUP_ID
#
if ! is_root; then
    fatal_error "This Docker container can only be run with a privileged user"
fi
message "Activating the log file for this script"
  set_logfile "$QSERVER_LOG_FILE"

if [[ ! -d "$APPDATA" ]]; then
    fatal_error "The directory '$APPDATA' has not been correctly mounted" \
                "The Docker command might be missing the parameter -v {DIR_TO_MOUNT}:/appdata" \
                "There might also be issues with SELinux (verify the SELinux settings or try disabling it temporarily)"
fi
if [[ -n "$USER_ID" ]]; then
    message "Validating USER_ID"
    validate_integer "$USER_ID" || \
        fatal_error "USER_ID must be a valid integer value"
fi
if [[ -n "$GROUP_ID" ]]; then
    message "Validating GROUP_ID"
    validate_integer "$GROUP_ID" || \
        fatal_error "GROUP_ID must be a valid integer value"
fi

# switch to the app's directory
message "Switching to the app's directory: $APP"
  cd "$APP" \
   || fatal_error "Failed to change directory to $APP"

# determine the configuration file extension (.config/.ini)
QSERVER_CONFIG_EXT='.config'
if [[ ! -f "$QSERVER_CONFIG_FILE.config" ]]; then
    if [[ -f "$QSERVER_CONFIG_FILE.ini" ]]; then
        QSERVER_CONFIG_EXT='.ini'
    fi
fi
QSERVER_CONFIG_FILE="${QSERVER_CONFIG_FILE}${QSERVER_CONFIG_EXT}"
CONFIG_NAME="${CONFIG_NAME}${QSERVER_CONFIG_EXT}"

# if the configuration file exists, process it variable by variable.
# otherwise, use the default configuration.
if [[ -f "$QSERVER_CONFIG_FILE" ]]; then
    message "Processing configuration file: $CONFIG_NAME"
    begin_config_vars      "$QSERVER_CONFIG_FILE"
    for_each_config_var_in "$QSERVER_CONFIG_FILE" process_config_var
    end_config_vars        "$QSERVER_CONFIG_FILE"
else
    message "No configuration file found: $CONFIG_NAME (or .ini)"
    message "Using default configuration"
fi

# get the user/group that will be used by users when accessing files.
# the first valid ID found will be used in the following order:
#  1) env variables `USER_ID`, `GROUP_ID` defined when launching the container
#  2) config variables `CFG_USER_ID`, `CFG_GROUP_ID`
#  3) the user/group of the qsamba.config file
#
QSERVER_USER_ID=${USER_ID:-$CFG_USER_ID}
QSERVER_GROUP_ID=${GROUP_ID:-$CFG_GROUP_ID}

if [[ -z "$QSERVER_USER_ID" || -z "$QSERVER_GROUP_ID" ]]; then

    # If the user didn't provide USER_ID/GROUP_ID
    # then the configuration file must exist
    [[ -f "$QSERVER_CONFIG_FILE" ]] || \
        fatal_error "Unable to determine USER_ID/GROUP_ID because the configuration file was not found" \
                    "Please provide USER_ID and GROUP_ID environment variables when launching the container" \
                    "Alternatively, create a configuration file named $CONFIG_NAME, and the script will use the user/group from its file permissions"

    config_file_info=$(stat -c "%u %g" "$QSERVER_CONFIG_FILE")
    if [[ -z "$QSERVER_USER_ID" ]]; then
        message "USER_ID was not defined (obtaining ID from the file permissions of $CONFIG_NAME)"
        QSERVER_USER_ID=$( echo "$config_file_info" | cut -d' ' -f1)
    fi
    if [[ -z "$QSERVER_GROUP_ID" ]]; then
        message "GROUP_ID was not defined (obtaining ID from the file permissions of $CONFIG_NAME)"
        QSERVER_GROUP_ID=$(echo "$config_file_info" | cut -d' ' -f2)
    fi
    unset config_file_info
    unset USER_ID GROUP_ID
fi



# remove all pre-existing users
message "Resetting all users"
remove_all_samba_vusers "$SAMBA_CONF_FILE"
remove_qserver_user_and_group

# ensure the existence of the main user/group with the provided IDs
message "Ensuring existence of USER_ID/GROUP_ID [$QSERVER_USER_ID/$QSERVER_GROUP_ID]"
QSERVER_GROUP=$(add_qserver_group "$QSERVER_GROUP_ID") || exit 1
QSERVER_USER=$(add_qserver_user   "$QSERVER_USER_ID" "$QSERVER_GROUP") || exit 1



generate_resource_data resdata "$CFG_RESOURCE_LIST"

# create main samba configuration
message "Generating main Samba configuration"
print_samba_conf resdata > "$SAMBA_CONF_FILE"

# create configuration for each user
message "Generating user configurations"
echo "$CFG_USER_LIST" | \
while IFS='|' read -r username password resources; do
    if [[ -n $username && $username != 'guest' ]]; then
        output_file="$SAMBA_CONF_DIR/$username.conf"
        add_samba_vuser "$username" "$password"
        print_user_conf "$username" "$resources" resdata > "$output_file"
    fi
done

remove_resource_data resdata



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


