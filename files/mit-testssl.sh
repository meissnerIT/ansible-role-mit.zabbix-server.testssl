#!/usr/bin/env bash
#
# v2016-04-02-2

# ./testssl.sh --vulnerable --color 0 --quiet https://$1
#cat /tmp/testssl.sh-result-www.meissner.it \
#    | awk -v FIELDWIDTHS="1 42 100" -v OFS=": " \
#	'/^ .*(CVE|Renegotiation).*/ { gsub(/[ \t]+$/, "", $2); print $2,$3}' \
#    | grep -v "(OK)"

#logger -t $0 "Checking $1"

# cat /tmp/testssl.sh-result-www.meissner.it \
/usr/local/share/testssl.sh/testssl.sh --vulnerable --color 0 --quiet $1 \
    | grep "(NOT ok)"

