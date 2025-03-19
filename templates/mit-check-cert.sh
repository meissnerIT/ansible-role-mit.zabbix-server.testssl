#!{{ bash_bin }}
#
# Distributed via ansible - mit.zabbix-server.testssl
#
# v2020-06-08-1
# 2024-10-16: Added ca-certificates
# 2025-03-19: Added "certificate does not match"

set -e

if [ -d {{ mit_testssl_etc_dir }}/ca-certificates ]; then
    first=1
    for CA_CERT in $(find {{ mit_testssl_etc_dir }}/ca-certificates -maxdepth 1 -type f); do
        if [ $first -eq 1 ]; then
            TESTSSL_EXTRA_PARAMS="$TESTSSL_EXTRA_PARAMS --add-ca $CA_CERT"
            first=0
        else
            TESTSSL_EXTRA_PARAMS="$TESTSSL_EXTRA_PARAMS,$CA_CERT"
        fi
    done
fi

/opt/mit-testssl.sh/testssl.sh/testssl.sh --server-defaults --color 0 --quiet $TESTSSL_EXTRA_PARAMS $1 |
    egrep "(NOT ok|certificate does not match)" | paste -s -d, | xargs || true
