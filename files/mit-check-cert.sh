#!/usr/bin/env bash
#
# Distributed via ansible - mit.zabbix-server.testssl
#
# v2020-06-08-1

set -e

/usr/local/share/testssl.sh/testssl.sh --server-defaults --color 0 --quiet $1 \
    | grep "NOT ok" | paste -s -d, | xargs || true

