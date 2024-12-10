#!/opt/mit-testssl.sh/.venv/bin/python3
#
# Distributed via ansible - mit.zabbix-server.testssl
#
# #17257: Checks given host via zabbix-mit-testssl-helper (which calls
# testssl.sh) and reports back via zabbix_sender.
#
# Idempotent - can be called as often as you wish.
#
# zabbix-mit-testssl-caller -> zabbix-mit-testssl -> zabbix-mit-testssl-helper
#
# Example:
# zabbix-mit-testssl http www.meissner.it
# zabbix-mit-testssl smtp mail.meissner.it
# zabbix-mit-testssl imap mail.meissner.it
#
# v2023-03-15: Updated pyzabbix configuration
# v2023-05-09: Removed detect_version=False, no longer needed for pyzabbix 1.3.0
# v2023-09-14: Improved logging

# https://www.askpython.com/python/python-command-line-arguments
import argparse
import configparser
import os
import subprocess
import sys
import logging
import urllib3
# https://github.com/lukecyca/pyzabbix
from pyzabbix import ZabbixAPI

formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
shStdout = logging.StreamHandler(sys.stdout)
shStdout.setFormatter(formatter)
shStderr = logging.StreamHandler(sys.stderr)
shStderr.setFormatter(formatter)
shStderr.setLevel(logging.ERROR)

log = logging.getLogger(os.path.basename(__file__))
log.addHandler(shStdout)
log.addHandler(shStderr)
log.setLevel(logging.INFO)

parser = argparse.ArgumentParser()
parser.add_argument("protocol")
parser.add_argument("host")
args = parser.parse_args()

configParser = configparser.RawConfigParser()
configFilePath = "{{ mit_testssl_etc_dir }}/mit-testssl.sh.conf"
configParser.read(configFilePath)

##############################################################################
# mit-pyzabbix.py v2023-09-20
##############################################################################
# https://github.com/lukecyca/pyzabbix/issues/157
# detect_version=False only needed for pyzabbix < 1.3
zapi = ZabbixAPI(configParser.get('DEFAULT', 'zabbix-api.url'))
if configParser.has_option('DEFAULT', 'zabbix-api.verify'):
    # https://requests.readthedocs.io/en/master/user/advanced/#ssl-cert-verification
    zapi.session.verify = configParser.get('DEFAULT', 'zabbix-api.verify')
elif not configParser.getboolean('DEFAULT', 'zabbix-api.certificate_verification', fallback=True):
    # https://urllib3.readthedocs.io/en/latest/advanced-usage.html#ssl-warnings
    urllib3.disable_warnings()
    zapi.session.verify = False
    log.info("Disabled certificate verification - please don't use this in production!")

# https://requests.readthedocs.io/en/latest/user/advanced/#proxies
if configParser.has_option('DEFAULT', 'zabbix-api.proxy'):
    proxies = {
        'http': configParser.get('DEFAULT', 'zabbix-api.proxy'),
        'https': configParser.get('DEFAULT', 'zabbix-api.proxy')
    }
    zapi.session.proxies.update(proxies)

zapi.login(configParser.get('DEFAULT', 'zabbix-api.user'), configParser.get('DEFAULT', 'zabbix-api.password'))
log.debug("Connected to Zabbix API Version %s" % zapi.api_version())

hosts = zapi.host.get(filter={"host": args.host})
if not hosts:
    log.error("Could not find host '%s'" % args.host)
    exit(1)

host = hosts[0]
log.debug("Found %s (id=%s)" % (host['host'], host['hostid']))

if args.protocol == "http":
    macroNamePort = "{$TLS_PORT}"
    macroNameHost = "{$TLS_HOST}"
    defaultPort = 443
else:
    macroNamePort = "{$TLS_" + args.protocol.upper() + "_PORT}"
    macroNameHost = "{$TLS_" + args.protocol.upper() + "_HOST}"
    if args.protocol == "smtp":
        defaultPort = 25
    elif args.protocol == "imap":
        defaultPort = 143

usermacroTlsHost = zapi.usermacro.get(hostids=host['hostid'], filter={ "macro": macroNameHost })
if usermacroTlsHost:
    tlsHost = usermacroTlsHost[0]["value"]
    log.debug("Using host %s based on macro %s" % (tlsHost, macroNameHost))
else:
    hostinterface = zapi.hostinterface.get(hostids=host['hostid'])
    log.debug(hostinterface)
    if hostinterface[0]['useip']=='1':
        tlsHost = hostinterface[0]['ip']
    else:
        tlsHost = hostinterface[0]['dns']
    log.debug("Using host %s based on host interface" % tlsHost)

usermacroTlsPort = zapi.usermacro.get(hostids=host['hostid'], filter={ "macro": macroNamePort })
if usermacroTlsPort:
    tlsPort = usermacroTlsPort[0]["value"]
else:
    tlsPort = defaultPort
log.debug("Using port %s based on macro %s" % (tlsPort, macroNamePort))

url = "%s:%s" % (tlsHost, tlsPort)

testsslCmd = ["/opt/mit-testssl.sh/bin/mit-testssl.sh-helper", args.protocol, url]
#testsslCmd = ["echo"]
log.info("Checking %s with protocol %s via %s" % (host['host'], args.protocol, url))
testsslCmdCompleted = subprocess.run(testsslCmd, stdout = subprocess.PIPE, stderr=subprocess.PIPE)
if testsslCmdCompleted.returncode == 0 and len(testsslCmdCompleted.stderr) == 0:
    testsslOutput = testsslCmdCompleted.stdout.decode('utf-8').strip()
    log.debug("Got '%s' from %s" % (testsslOutput, testsslCmd))
    zabbix_key = 'mit-testssl-' + args.protocol
    zabbix_sender_cmd = [r'zabbix_sender', '-z', configParser.get('DEFAULT', 'zabbix.host'), '-s', host['host'], '-k', zabbix_key, '-o', '%s' % (testsslOutput)]
    # When called from zabbix (e.g. Frontend → Proxy → mit-testssl.sh)
    # PATH is not set on FreeBSD.
    my_env = os.environ.copy()
    my_env["PATH"] = f"/usr/local/bin:{my_env['PATH']}"
    log.debug("Executing %s" % zabbix_sender_cmd)
    try:
        zabbix_sender_output = subprocess.check_output(zabbix_sender_cmd, env=my_env).strip()
        log.debug("Called %s, got %s" % (zabbix_sender_cmd, zabbix_sender_output))
        log.info("Transmitted result '%s' for host %s with key %s to zabbix server" % (testsslOutput, host['host'], zabbix_key))
    except:
        log.error("Got error while executing %s" % (zabbix_sender_cmd))
        if zabbix_sender_output:
            log.error(zabbix_sender_output)
else:
    log.warning(f"Got returncode {testsslCmdCompleted.returncode} and stderr='{testsslCmdCompleted.stderr.decode('utf-8')}' while checking host['host'] via {testsslCmd}")
    # Do nothing, Zabbix has a trigger for nodata(2d)
log.info("READY.")

