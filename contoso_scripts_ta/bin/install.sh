#!/bin/bash
#
# Installs Splunk Server, sets ownership and pushes deploymentclient.conf
# Daniel Wilson <daniel.p.wilson@live.com>
# Ver 2.4.2019.1

# TODO(dwilson): Add startup details
# TODO(dwilson): add user-seed.conf to randomize the password

### Globals
# Set path to installer, use a link
# ln -f -s splunk-8.0.1-6db836e2fb9e-linux-2.6-x86_64.rpm splunk
# cd /root/Downloads
#  wget -O splunk-8.0.3-a6754d8441bf-linux-2.6-x86_64.rpm 'https://www.splunk.com/bin/splunk/DownloadActivityServlet?architecture=x86_64&platform=linux&version=8.0.3&product=splunk&filename=splunk-8.0.3-a6754d8441bf-linux-2.6-x86_64.rpm&wget=true'
# mv splunk-8.0.3-a6754d8441bf-linux-2.6-x86_64.rpm splunk.rpm

  declare -r strRpmPath="/root/Downloads/splunk.rpm"
  declare -r strThisFile="${0##*/}"

### Functions

#######################################
# Sends errors to STDERR and logger
# Globals:
#   None
# Arguments:
#   String
# Returns:
#   None
#######################################
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: serverity=ERROR app=${0##*/} $@" >&2
  logger "severity=ERROR app=${0##*/} $@"
}

#######################################
# Captures start time, logs the md5 sums and the change
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
start_script() {
  intStart=`date +%s`
  if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run by user=root"
    exit 1
  fi
  echo "### Starting Install of Splunk Server ###"
  rpm -qa splunk
  logger "severity=INFORMATIONAL app=${0##*/} status=starting md5 is hash=`md5sum $strThisFile`"
  logger "severity=INFORMATIONAL app=${0##*/} action=install package=`readlink -f $strRpmPath`"
}

#######################################
# Logs runtime and exits script
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
close() {
  intEnd=`date +%s`
  intRuntime=$((end-start))
  logger "app=$strThisFile status=stopped run time was duration=$intRuntime seconds"
}

#######################################
# Installs Splunk and changes the owner to Splunk
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
install_splunk() {
  rpm -i $strRpmPath
  chown -R splunk:splunk /opt/splunk
}

#######################################
# Creates the local admin account and sets password insecurely to 'changeme'
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
set_localadmin() {
  /opt/splunk/bin/splunk enable boot-start -user splunk --accept-license --no-prompt --answer-yes
  echo "# user-seed.conf" >> /opt/splunk/etc/system/local/user-seed.conf
  echo "" >> /opt/splunk/etc/system/local/user-seed.conf
  echo "" >> /opt/splunk/etc/system/local/user-seed.conf
  echo "[user_info]" >> /opt/splunk/etc/system/local/user-seed.conf
  echo "  USERNAME = Admin" >> /opt/splunk/etc/system/local/user-seed.conf
  echo "  PASSWORD = changeme2020" >> /opt/splunk/etc/system/local/user-seed.conf
  echo "Default password is changeme2020, now go change it and add to your password management system"

  echo "Moving to https and changing ports to 8443 for a secure bootstrap."
  echo "Consider removing /opt/splunk/etc/system/local/web.conf when local apps applied"
  echo "# web.conf" >> /opt/splunk/etc/system/local/web.conf
  echo "" >> /opt/splunk/etc/system/local/web.conf
  echo "[settings]" >> /opt/splunk/etc/system/local/web.conf
  echo "  enableSplunkWebSSL = True" >> /opt/splunk/etc/system/local/web.conf
  echo "  httpport = 8443" >> /opt/splunk/etc/system/local/web.conf
}

#######################################
# Sets init and starts Splunk
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
start_splunk() {
  echo "Copying a custom init with some THP and Ulimit settings added"
  cp ./splunk /etc/init.d/splunk
  chmod +x /etc/init.d/splunk
  echo "Starting"
  /etc/init.d/splunk start
}

#######################################
# Just a little reminder for users to check fw
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
get_fwstatus() {
  echo "FYI Config youre firewall as needed"
  systemctl status firewalld | grep -i Active
  systemctl status iptables | grep -i Active
}

#######################################
# Ensure Splunk can read local logs
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
set_logperm() {
  setfacl -Rm u:splunk:r-x,d:u:splunk:r-x /var/log
  sed -i 's/log_group = root/log_group = splunk/g' /etc/audit/auditd.conf
  chgrp -R splunk /var/log/audit
  chmod 0750 /var/log/audit
  chmod 0640 /var/log/audit/*
}

main() {
  if [ $(rpm -qa|grep -c splunk) -gt 0 ]; then
    err "Splunk already installed, exiting"
    close
    exit
  else
    start_script
    install_splunk
    set_localadmin
    start_splunk
    set_logperm
    get_fwstatus
    close
  fi
}

# Main
main

