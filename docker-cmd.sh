#!/usr/bin/env bash
# File    : docker-cmd.sh
# Brief   : Script to manage the docker image and container for this project
# Author  : Martin Rizzo | <martinrizzo@gmail.com>
# Date    : Feb 6, 2024
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


# Define parameters for managing the Docker image and container of the project.
#  - IMAGE_NAME     : Name of the Docker image associated with the project.
#  - CONTAINER_NAME : Name of the Docker container instantiated from the image.
#  - CONTAINER_PARAMETERS :
#      Parameters for configuring the Docker container. These parameters
#      are passed to the 'docker run' command for setting up port mappings,
#      environment variables, volumes, etc.
#      Make sure to properly format them by escaping newline characters '\'.
#
PROJECT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")" )
IMAGE_NAME='quick-samba-server'
IMAGE_USER='martinrizzo'
CONTAINER_NAME='samba-server'

# DEFAULT: standard parameters with user mapping and mounted directory
CONTAINER_PARAMETERS="
       {--USER}
       -v {DIR_TO_MOUNT}:/appdata:Z
       -p 139:139
       -p 445:445
"

# # NO USER/GROUP: parameters without user mapping (determined by configuration)
# CONTAINER_PARAMETERS="
#        -v {DIR_TO_MOUNT}:/appdata:Z
#        -p 139:139
#        -p 445:445
# "

# # AVAHI: parameters for network interface access (requires host network)
# CONTAINER_PARAMETERS="
#        {--USER}
#        -v {DIR_TO_MOUNT}:/appdata:Z
#        --network host
# "

# # ERROR: invalid parameters (no directory mounted at /appdata)
# CONTAINER_PARAMETERS="
#        {--USER}
#        -p 139:139
#        -p 445:445
# "

LOG_LEVEL='debug'  # | debug | info | warn | error | fatal |

#---------------------------- MESSAGE HANDLING -----------------------------#

RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
BLUE='\e[1;34m'
#PURPLE='\e[1;35m'
CYAN='\e[1;36m'
DEFAULT_COLOR='\e[0m'
PADDING='   '

# Display a regular message
message() {
    local message=$1
    echo -e "${PADDING}${GREEN}>${DEFAULT_COLOR} $message"
}

# Displays a warning message
warning() {
    local message=$1
    echo -e "${CYAN}[${YELLOW}WARNING${CYAN}]${YELLOW} $message${DEFAULT_COLOR}"
}

# Displays an error message
error() {
    local message=$1
    echo -e "${CYAN}[${RED}ERROR${CYAN}]${RED} $message.${DEFAULT_COLOR}"
}

# Displays a fatal error message and exits the script with status code 1
fatal_error() {
    local error_message=$1 info_message=$2
    error "$error_message"
    [[ -n "$info_message" ]] && echo -e "${CYAN}\xF0\x9F\x9B\x88  $info_message.${DEFAULT_COLOR}"
    exit 1
}

#-------------------------------- HELPERS ----------------------------------#

is_digit() {
    [[ "$1" =~ ^[0-9]$ ]]
}

# Checks if a Docker container is running
docker_container_is_running() {
    local status
    status=$(docker container inspect --format='{{.State.Status}}' "$1" 2>/dev/null)
    [[ $status = 'running' ]]
}

# Checks if a Docker container is stopped
docker_container_is_stopped() {
    local status
    status=$(docker container inspect --format='{{.State.Status}}' "$1" 2>/dev/null)
    [[ $status = 'exited' ]]
}

# Checks if a Docker image exists in the repository
docker_image_exists() {
    docker image inspect "$1" &> /dev/null
}

# Checks if a Docker container exists
docker_container_exists() {
    if [[ -n $(docker ps -a -q -f name="$1") ]]; then
        return 0  # container exists
    else
        return 1  # container does not exist
    fi
}

#-------------------------------- COMMANDS ---------------------------------#

# Build the Docker image using the current source code
build_image() {

    # if the image already exists then do nothing
    if docker_image_exists $IMAGE_NAME ; then
        warning "The image is already built, nothing to do."
        exit 0
    fi

    # build the Docker image
    echo "Building the Docker image..."
    if ! docker build -t $IMAGE_NAME . ; then
        fatal_error "Failed to build the Docker image."
    fi
    echo "Done! The container has been built."
}

# Build the latest released version and optionally push it to Docker Hub
build_last_release() {
    local push=$1
    local user token last_commit last_commit_tag
    local user_token_file="$PROJECT_DIR/docker-cmd.token"

    # check for uncommitted files in git
    if [[ -n $(git status --porcelain) ]]; then
        fatal_error "There are uncommitted changes in the repository" \
        "Please commit or stash them before pushing the image"
    fi

    # get the last commit tag
    last_commit=$(git rev-parse HEAD)
    last_commit_tag=$(git describe --exact-match --tags "$last_commit" 2>/dev/null)
    if [[ -z "$last_commit_tag" ]]; then
        fatal_error "No tag found on the latest commit." \
        "Please check out the specific tag you want to generate."
    fi

    # read Docker Hub credentials from the user_token_file
    if [[ -e "$user_token_file" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            if [[ -z "$user" ]]; then
                user="$line"
            else
                token="$line"
                break
            fi
        done < "$user_token_file"
    fi

    # removes all existing Docker images and containers related
    # to the project and rebuilds the image from scratch
    clear_docker_resources
    build_image

    # generate container tags and remove intermediate resources
    user=${user:-$IMAGE_USER}
    docker tag "$IMAGE_NAME" "$user/$IMAGE_NAME:$last_commit_tag"
    docker tag "$IMAGE_NAME" "$user/$IMAGE_NAME:latest"
    clear_docker_resources

    # if not pushing to Docker Hub, the function ends here
    if [[ "$push" != 'push' ]]; then
        return 0
    fi

    # check if the user/token file exists
    if [[ ! -e "$user_token_file" ]]; then
        fatal_error "To push the image, the file docker-cmd.token must exist" \
        "The file should contain the Docker Hub username on the first line and the token on the second line"
    fi

    # login to Docker Hub
    if ! echo "$token" | docker login --username "$user" --password-stdin
    then
        fatal_error "Docker login failed. Please check your credentials and try again"
    fi

    # push tags and logout
    if ! docker push "$user/$IMAGE_NAME:$last_commit_tag" ; then
        fatal_error "Failed to push the Docker image"
    fi
    if ! docker push "$user/$IMAGE_NAME:latest" ; then
        fatal_error "Failed to push the Docker image"
    fi
    docker logout

    echo "Docker image pushed successfully: $user/$IMAGE_NAME:$last_commit_tag"
}

# Stop and remove container and image
clear_docker_resources() {

    # stop the container if it's running
    if [[ "$(docker ps -q -f name=$CONTAINER_NAME)" ]]; then
        echo "Stopping the existing container..."
        docker stop $CONTAINER_NAME
    fi

    # remove the container if it exists
    if [[ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]]; then
        echo "Removing the existing container..."
        docker rm $CONTAINER_NAME
    fi

    # remove the image if it exists
    if [[ "$(docker images -q $IMAGE_NAME)" ]]; then
        echo "Removing the existing image..."
        docker rmi $IMAGE_NAME
    fi

    echo "Done! Docker resources cleared."
}

# List images and containers
list_docker_info() {
    echo
    echo -e '    \e[1;32mDOCKER IMAGES'
    docker images | awk 'NR==1 {print "    \033[0;30;42m" $0 "\033[0m"} NR>1 {print "    " $0 }'
    echo
    echo -e '    \e[1;32mDOCKER CONTAINERS'
    docker ps -a  | awk 'NR==1 {print "    \033[0;30;42m" $0 "\033[0m"} NR>1 {print "    " $0 }'
    echo
}

# Run the container with specified directory to mount and user permissions
run_container() {
    local dir_to_mount=$1 root=$2
    local user_parameter user_display_name

    # set user parameters based on whether the container is run as root or not
    if [[ $root == 'root' ]]; then
        user_parameter="-e USER_ID=$(id -u) -e GROUP_ID=$(id -g)"
        user_display_name='root'
    else
        user_parameter="--user $(id -u):$(id -g)"
        user_display_name="user <$(id -u):$(id -g)>"
    fi

    # remove the container if it is running before starting a new one
    remove_container

    # build the image if it does not exist.
    if ! docker_image_exists $IMAGE_NAME ; then
        build_image
    fi

    # start a new container with the specified parameters.
    echo -e '\n-----------------------------------------------------------'
    echo -e "$BLUE$0"
    message "Starting the '$CONTAINER_NAME' container as $user_display_name..."
    local parameters=$CONTAINER_PARAMETERS
    parameters=${parameters//'{DIR_TO_MOUNT}'/$dir_to_mount}
    parameters=${parameters//'{--USER}'/$user_parameter}
    message "docker --log-level=$LOG_LEVEL run $parameters       --name '$CONTAINER_NAME' '$IMAGE_NAME'"
    # shellcheck disable=2086
    docker "--log-level=$LOG_LEVEL" run $parameters --name "$CONTAINER_NAME" "$IMAGE_NAME"
}

# Run the container using the requested example number
run_example() {
    local example_number=${1:-1} root=$2
    if [[ ! $example_number =~ ^[1-9]$ ]]; then
        fatal_error "Example number must be between 1 and 9"
    fi

    # validate the existence of the directory containing the example
    example_dir="${PROJECT_DIR}/example${example_number}"
    if [[ ! -d $example_dir ]]; then
        fatal_error "The requested example '$example_number' is not available" \
            "Please verify that the example is implemented in the directory './example${example_number}'"
    fi
    run_container "$example_dir" "$root"
}

# Stop the container if it's currently running
stop_container() {
    if docker_container_is_running $CONTAINER_NAME ; then
        message "Stopping the '$CONTAINER_NAME' container..."
        docker stop $CONTAINER_NAME 1> /dev/null && \
          message "The '$CONTAINER_NAME' container has been successfully stopped."
    fi
}

# Stop and remove the container if it exists
remove_container() {
    stop_container
    if docker_container_exists $CONTAINER_NAME ; then
        message "Removing the '$CONTAINER_NAME' container..."
        docker rm $CONTAINER_NAME 1> /dev/null && \
          message "The '$CONTAINER_NAME' container has been successfully removed."
    fi
}

restart_container() {
    docker restart $CONTAINER_NAME
}

open_console_in_container() {
    docker exec -it "$CONTAINER_NAME" /bin/sh -l
}

show_container_logs() {
    if ! docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        echo "Error: The container $CONTAINER_NAME does not exist." >&2
        return 1
    fi
    echo "Showing logs for container $CONTAINER_NAME..."
    docker logs $CONTAINER_NAME
}

execute_command_in_container() {
    fatal_error "Not implemented"
}

show_container_status() {
    fatal_error "Not implemented"
}

#===========================================================================#
# ///////////////////////////////// MAIN ////////////////////////////////// #
#===========================================================================#

HELP="
Usage: ./docker-cmd.sh [OPTIONS] COMMAND

A script to manage the Docker image and container for this project.

Options:
  -h, --help     Display this help message and exit
  -v, --version  Display version information and exit

Commands:
  build               Build the current Docker image
  clean               Clear Docker resources
  list                List Docker information
  run[number]         Run the example specified by [number] as root
  urun[number]        Run the example specified by [number] as an unprivileged user
  stop                Stop the Docker container
  restart             Restart the Docker container
  console             Open a console in the Docker container
  build-last-release  Build the latest released version of the Docker image
  push                Push the latest version of the Docker image to Docker Hub
  logs                Show Docker container logs
  exec                Execute a command in the Docker container
  status              Show the status of the Docker container

  To clean Docker resources:
    ./docker-cmd.sh clean

  To run the Docker container with the default example as root:
    ./docker-cmd.sh run

  To run the Docker container with example 2 as an unprivileged user:
    ./docker-cmd.sh urun2
"

# check if the user requested help or the image version
if [ $# -eq 0 ]; then
    echo "$HELP" ; exit 0
fi
for param in "$@"; do
    case "$param" in
        -h|--help)
            echo "$HELP" ; exit 0
            ;;
        -v|--version)
            echo "${0##*/}" "v0.1" ; exit 0
            ;;
        -*)
            fatal_error "Option '$param' is not supported"
            ;;
    esac
done

# process each command requested by the user
cd "$PROJECT_DIR/src" \
 || fatal_error "Failed to change directory to $PROJECT_DIR/src"
while [[ $# -gt 0 ]]; do

    param=$1
    case "$param" in
        build)
            build_image
            ;;
        clean)
            clear_docker_resources
            ;;
        run | run[1-9])
            example='1'
            if is_digit "${param#'run'}"; then
                example="${param#'run'}"
            elif [[ $param == 'run' ]] && is_digit "$2"; then
                shift ; example=$1
            fi
            run_example "$example" 'root'
            ;;
        urun | urun[1-9])
            example='1'
            if is_digit "${param#'urun'}"; then
                example="${param#'urun'}"
            elif [[ $param == 'urun' ]] && is_digit "$2"; then
                shift ; example=$1
            fi
            run_example "$example"
            ;;
        stop)
            stop_container
            ;;
        remove)
            remove_container
            ;;
        restart)
            restart_container
            ;;
        console)
            open_console_in_container
            ;;
        build-last-release)
            build_last_release
            ;;
        push)
            build_last_release 'push'
            ;;
        list)
            list_docker_info
            ;;
        logs)
            show_container_logs
            ;;
        exec)
            execute_command_in_container
            ;;
        status)
            show_container_status
            ;;

        image-exists)
            docker_image_exists $IMAGE_NAME && echo YES || echo NO
            ;;
        container-exists)
            docker_container_exists $CONTAINER_NAME && echo YES || echo NO
            ;;
        is-running)
            docker_container_is_running $CONTAINER_NAME && echo YES || echo NO
            ;;
        is-stopped)
            docker_container_is_stopped $CONTAINER_NAME && echo YES || echo NO
            ;;
        *)
            fatal_error "Unknown command '$param'"
            ;;
    esac
    shift

done
