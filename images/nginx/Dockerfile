# Copyright 2015 The Kubernetes Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


FROM BASEIMAGE

CROSS_BUILD_COPY qemu-ARCH-static /usr/bin/

COPY build.sh install_lua_resty_waf.sh /

RUN clean-install bash

RUN echo deb http://deb.debian.org/debian experimental main >> /etc/apt/sources.list \
 && echo deb http://deb.debian.org/debian unstable main >> /etc/apt/sources.list \
 && printf 'Package: *\nPin: release a=stable\nPin-Priority: 700\n\nPackage: *\nPin: release a=testing\nPin-Priority: 650\n\nPackage: *\nPin: release a=unstable\nPin-Priority: 600\n\nPackage: *\nPin: release a=experimental\nPin-Priority: 550\n' | install -D /dev/stdin /etc/apt/preferences.d/pinning \
 && printf 'Package: openssl\nPin: release a=experimental\nPin-Priority: 700\n' | install -D /dev/stdin /etc/apt/preferences.d/openssl \
 && printf 'Package: libssl*\nPin: release a=experimental\nPin-Priority: 700\n' | install -D /dev/stdin /etc/apt/preferences.d/libssl \
 && printf 'Package: libc6*\nPin: release a=unstable\nPin-Priority: 700\n' | install -D /dev/stdin /etc/apt/preferences.d/libc6 \
 && printf 'Package: libc-*\nPin: release a=unstable\nPin-Priority: 700\n' | install -D /dev/stdin /etc/apt/preferences.d/libc

RUN /build.sh

# Create symlinks to redirect nginx logs to stdout and stderr docker log collector
# This only works if nginx is started with CMD or ENTRYPOINT
RUN ln -sf /dev/stdout /var/log/nginx/access.log
RUN ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
