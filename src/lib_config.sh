#!/bin/busybox sh
# File    : lib_config.sh
# Brief   : Implements functions to read configuration files.
# Author  : Martin Rizzo | <martinrizzo@gmail.com>
# Date    : Mar 19, 2024
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


#-------------------------------- HELPERS ----------------------------------#

NEWLINE="
"

# Remove leading and trailing whitespace from a string.
# Example: trimmed_text=$(trim "  Hello, world!  ")
#
function trim() {
    local text="$*"
    text="${text#"${text%%[![:space:]]*}"}"
    echo "${text%"${text##*[![:space:]]}"}"
}

# Convert text to uppercase.
# Example: uppercased_text=$(toupper "hello, world!")
#
function toupper() {
    local text="$*"
    echo "$text" | tr '[:lower:]' '[:upper:]'
}


#--------------------------- CONFIG VARS HANDLING --------------------------#

# Iterate through each configuration variable in a specified configuration file
#
# Usage:
#   for_each_config_var_in <config_file> <func>
#
# Parameters:
#   - config_file: the path to the configuration file to iterate through.
#   - func: the function to be called for each variable found.
#
# Example:
#   for_each_config_var_in "/path/to/config.conf" process_config_var
#
#   This will iterate through each variable in 'config.conf' and call the
#   process_config_var function with the var name and value as arguments.
#
function for_each_config_var_in() {
    local config_file=$1 func=$2
    local line_number=0 varname value

    # read the file line by line
    while IFS= read -r line; do
        line_number=$((line_number + 1))

        # remove leading whitespace
        line="${line#"${line%%[![:space:]]*}"}"

        # ignore empty lines and comments
         if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi

        # error if line starts with '=' and there is no variable name
        if [[ "$line" == \=* ]]; then
            "$func" PRINT_ERROR "variable name is missing on line $line_number"
            exit 1
        fi

        value=$(echo "$line"   | cut -d'=' -f2-)
        varname=$(echo "$line" | cut -d'=' -f1)
        varname=$(trim    "$varname")
        varname=$(toupper "$varname")
        if ! "$func" "$varname" "$value" ; then
            "$func" PRINT_ERROR "there was an error at line $line_number"
            exit 1
        fi

    done < "$config_file"
}

# Format a value according to specified format rules.
#
# Usage:
#   format_value <values> <format1> [<format2> ...]
#
# Parameters:
#   - values: a string with the value or values to be formatted.
#   - format1, format2, ...: one or more format rules to apply to each value.
#
# Example:
#   values=$(format_value "/path/to/dir|text|true" dir txt bool)
#
#   This will format the given values according to the specified rules:
#   "dir" for directory format, "txt" for text format, and "bool" for boolean.
#
# The function iterates through each parameter in the provided string,
# applying the corresponding format rules. The available format rules are:
#    - reslist : Removes all spaces.
#    - dir     : Removes leading and trailing slashes from a directory path.
#    - txt     : Removes leading and trailing double quotes from a text string.
#    - bool    : Standardizes it to either TRUE or FALSE.
#    - name|user|pass: No modification is applied.
#
function format_value() {
    local line=$1
    OLD_IFS=$IFS ; IFS='|'

    local first=true
    for param in $line; do
        local format=$2 ; shift
        param=$(trim "$param")
        case $format in

            # resource list - (remove any whitespace)
            reslist)
                param=$(echo "$param" | sed 's/ //g')
                ;;

            # directory - (remove leading and trailing slashes)
            dir)
                param=${param#/}
                param=${param%/}
                ;;

            # text - (remove double quotes)
            txt)
                param=${param#\"}
                param=${param%\"}
                ;;

            # boolean - (standardize to TRUE or FALSE)
            bool)
                param=$(toupper "$param")
                if [[ $param == TRUE || $param == YES ]]; then
                    param=true
                elif [[ $param == FALSE || $param == NO ]]; then
                    param=false
                else
                    return 1
                fi
                ;;

            # password - (verificar si esta codificado en {base64})
            pass)
                if [[ "$param" == \{*\} ]]; then
                    param=${param#\{}
                    param=${param%\}}
                    param=$(echo "$param" | base64 -d)
                fi
                ;;

            # user name/user - (no modification needed)
            name|user)
                ;;

            # default case: continue to next iteration
            *)
                continue
                ;;

        esac
        [[ "$first" ]] && echo -n "$param" || echo -n "|$param"
        first=
    done

    echo
    IFS=$OLD_IFS
    return 0
}

function find_config_values() {
    local value_name=$1 value_list=$2
    echo "$value_list" | grep "^$value_name|"
}


