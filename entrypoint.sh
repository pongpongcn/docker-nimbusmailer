#!/usr/bin/env sh
set -e

cp -f /etc/resolv.conf /var/spool/postfix/etc/resolv.conf

exec "$@"