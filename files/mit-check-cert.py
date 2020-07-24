#!/usr/bin/env python
#
# Distributed via ansible - mit.zabbix-server.testssl
#
# Idempotent - can be called as often as you wish.

# https://www.askpython.com/python/python-command-line-arguments
import argparse
import ConfigParser
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

parser = argparse.ArgumentParser()
parser.add_argument("host")
parser.add_argument("vhost")
parser.add_argument("port")
args = parser.parse_args()

configParser = ConfigParser.RawConfigParser()   
configFilePath = r'/etc/zabbix/zabbix_agentd-mit-testssl.sh.conf'
configParser.read(configFilePath)
zabbix_api_user = configParser.get('DEFAULT', 'zabbix-api.user')
zabbix_api_password = configParser.get('DEFAULT', 'zabbix-api.password')
zabbix_api_url = configParser.get('DEFAULT', 'zabbix-api.url')
zabbix_host = configParser.get('DEFAULT', 'zabbix.host')

# https://stackoverflow.com/questions/419163/what-does-if-name-main-do
zapi = ZabbixAPI(zabbix_api_url)
zapi.login(zabbix_api_user, zabbix_api_password)
log.debug("Connected to Zabbix API Version %s" % zapi.api_version())

url = "https://%s:%s" % (args.vhost, args.port)
testsslCmd = ["/usr/lib/zabbix/externalscripts/mit-check-cert.sh", url]
log.debug("Executing %s" % (testsslCmd))
log.info("Checking %s" % (url))
testsslOutput = subprocess.check_output(testsslCmd).strip()
log.debug("Got '%s' from %s" % (testsslOutput, testsslCmd))
zabbixSenderCmd = [r'zabbix_sender', '-z', zabbix_host, '-s', args.host, '-k', 'mit-check-cert.sh[%s]' % (args.vhost), '-o', '%s' % (testsslOutput)]
log.debug("Executing %s" % zabbixSenderCmd)
try:
    zabbixSenderOutput = subprocess.check_output(zabbixSenderCmd).strip()
    log.debug("Called %s, got %s" % (zabbixSenderCmd, zabbixSenderOutput))
    log.info("Transmitted result '%s' for %s to zabbix server" % (testsslOutput, args.host))
except:
    log.error("Got error while executing %s" % (zabbixSenderCmd))
    log.error(zabbixSenderOutput)
log.debug("READY.")

