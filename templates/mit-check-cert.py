#!/opt/mit-testssl.sh/.venv/bin/python3
#
# Distributed via ansible - mit.zabbix-server.testssl
#
# Idempotent - can be called as often as you wish.

# https://www.askpython.com/python/python-command-line-arguments
import argparse
import configparser
import os
import subprocess
import sys
import logging
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
#log.setLevel(logging.DEBUG)

#logpz = logging.getLogger('pyzabbix')
#logpz.addHandler(shStdout)
#logpz.setLevel(logging.DEBUG)

##############################################################################
# Read command line arguments
##############################################################################

parser = argparse.ArgumentParser()
parser.add_argument("host")
parser.add_argument("vhost")
parser.add_argument("port")
args = parser.parse_args()

configParser = configparser.RawConfigParser()
configFilePath = r'/etc/zabbix/zabbix_agentd-mit-testssl.sh.conf'
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

url = "https://%s:%s" % (args.vhost, args.port)
testsslCmd = ["/opt/mit-testssl.sh/bin/mit-check-cert.sh", url]
log.debug("Executing %s" % (testsslCmd))
log.info("Checking %s" % (url))
testsslCmdCompleted = subprocess.run(testsslCmd, stdout = subprocess.PIPE, stderr=subprocess.PIPE)
if testsslCmdCompleted.returncode == 0 and len(testsslCmdCompleted.stderr) == 0:
    testsslOutput = testsslCmdCompleted.stdout.decode('utf-8').strip()
    log.debug("Got '%s' from %s" % (testsslOutput, testsslCmd))
    zabbixSenderCmd = [r'zabbix_sender', '-z', configParser.get('DEFAULT', 'zabbix.host'), '-s', args.host, '-k', 'mit-check-cert.sh[%s:%s]' % (args.vhost, args.port), '-o', '%s' % (testsslOutput)]
    log.debug("Executing %s" % zabbixSenderCmd)
    try:
        zabbixSenderOutput = subprocess.check_output(zabbixSenderCmd).strip()
        log.debug("Called %s, got %s" % (zabbixSenderCmd, zabbixSenderOutput))
        log.info("Transmitted result '%s' for %s to zabbix server" % (testsslOutput, args.host))
    except:
        log.error("Got error while executing %s" % (zabbixSenderCmd))
        log.error(zabbixSenderOutput)
else:
    log.warning(f"Got returncode {testsslCmdCompleted.returncode} and stderr='{testsslCmdCompleted.stderr.decode('utf-8')}' while checking host['host'] via {testsslCmd}")
log.debug("READY.")
