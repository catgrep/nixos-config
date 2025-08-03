# SPDX-License-Identifier: GPL-3.0-or-later
FROM alpine:latest

# last alpine release that provides dhclient
RUN echo "https://dl-cdn.alpinelinux.org/alpine/v3.19/main" > /etc/apk/repositories \
    && echo "https://dl-cdn.alpinelinux.org/alpine/v3.19/community" >> /etc/apk/repositories

RUN apk add --no-cache \
    dhclient \
    bind-tools \
    curl \
    bash
