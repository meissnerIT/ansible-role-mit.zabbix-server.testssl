#!/usr/bin/env bash
#
# v2016-04-02-3

# cat /tmp/testssl.sh-result-www.meissner.it \
/usr/local/share/testssl.sh/testssl.sh --vulnerable --color 0 --quiet $1 \
    | grep "(NOT ok)"

