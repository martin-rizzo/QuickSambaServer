# File    : Dockerfile
# Brief   : Dockerfile for setting up QuickSambaServer
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

# Use Alpine Linux as the base image for lightweight containerization
FROM alpine:3.19
MAINTAINER Martin Rizzo <martinrizzo@gmail.com>

# Copy project setup files to the /root directory:
#   - lib_config.sh        : configuration reader module
#   - lib_logfile.sh       :
#   - lib_utils.sh         : utility functions module
#   - entrypoint.sh        : container startup script
WORKDIR /root
COPY lib_config.sh lib_logfile.sh lib_utils.sh entrypoint.sh ./

# 1) Install samba & tini
# 2) Adds some aliases for convenience (useful for CLI interaction)
# 3) Set execute permissions for scripts
RUN set -ex \
\
&&  apk --no-cache --no-progress  update                        \
&&  apk --no-cache --no-progress add samba tini                \
\
&&  file='/etc/profile.d/ls_aliases.sh'                        \
&&  echo "alias ll='ls -lh --group-directories-first'" > $file \
&&  echo "alias ll.='ls -l -d .* --color=auto'"        > $file \
\
&&  chmod +x entrypoint.sh

## Expose Samba ports
EXPOSE 137/udp 138/udp 139 445

# Define the entry point script for container startup
ENTRYPOINT ["/sbin/tini", "--", "/root/entrypoint.sh"]