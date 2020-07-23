#!/bin/bash
# Installs Splunk Universal Forwarder, sets ownership of files and pushes deploymentclient.conf
# Daniel Wilson <daniel.p.wilson@live.com>
# ver 6.9.2020.1

# TODO(dwilson): Add Debian Support
# TODO(dwilson): Add help menu
# TODO(dwilson): We need root for Splunk_TA_nix, but might want an argument to disable that. 
# TODO(dwilson): Cert management next
# TODO(dwilson): Script should check for ports listening and provide FW guidance
# TODO(dwilson): Script should verify wget is installed and install if needed

# Globals
  declare -r strArg1="$1"
  declare -r strThisFile="${0##*/}"
  declare -r EL_VERSION=`rpm -qa \*-release | grep -Ei "oracle|redhat|centos" | cut -d"-" -f3 | cut -c 1`
  declare -r OS_VENDOR=`grep ^NAME /etc/os-release | awk -F '[" ]' '{print $2}'`
  declare -r src_ip=$(hostname -I)

### Functions

#######################################
# err, informational
# functions used for logging and stdout
# Globals: 0
#   None
# Arguments: 1
#   String
# Returns: 0
#   None
#######################################
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: serverity=ERROR src_ip=${src_ip} app=${0##*/} $@" >&2
  logger "severity=ERROR app=${0##*/} $@"
}

informational() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: serverity=INFORMATIONAL src_ip=${src_ip} app=${0##*/} $@" >&2
  logger "severity=INFORMATIONAL app=${0##*/} $@"
}

#######################################
# start_script
# Captures start time, logs the md5sums and checks the user and OS
# Globals:0
#   None
# Arguments:0
#   None
# Returns:0
#   None
#######################################
start_script() {
  intStart=`date +%s`
  # Check if OS is related to Redhat
  if [[ ! -f /etc/redhat-release ]]; then
    err "status=stopped message=\"Bad OS\" ";
    exit 1; else
    informational "vendor=\"RedHat Compatible\" status=starting"
  fi

  # check for root
  if [ "$EUID" -ne 0 ]; then
    err "status=stopped message=\"Please run as root\" "
    exit
  fi
  informational "status=starting md5 is hash=`md5sum $strThisFile`"

  if [ "$strArg1" = "uninstall" ]; then
    /opt/splunk/bin/splunk stop
    /opt/splunkforwarder/bin/splunk stop
    yum remove splunk -y
    yum remove splunkforwarder -y
    rm -rf /opt/splunkforwarder
    exit
  fi

}

#######################################
# install_uf
# Install Splunk Forwarder
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
install_uf() {
  echo $1
  if [ "$strArg1" = "yum" ]; then
    informational "install with yum"
    yum -y install splunkforwarder
  else
    informational "Yum not specified, curl/rpm install"
    wget -O splunkforwarder-8.0.2-a7f645ddaf91-linux-2.6-x86_64.rpm 'https://www.splunk.com/bin/splunk/DownloadActivityServlet?architecture=x86_64&platform=linux&version=8.0.2&product=universalforwarder&filename=splunkforwarder-8.0.2-a7f645ddaf91-linux-2.6-x86_64.rpm&wget=true'
    rpm -i splunkforwarder-8.0.2-a7f645ddaf91-linux-2.6-x86_64.rpm
  fi
}

#######################################
# set_startup
# Enables Splunk to start at boot. Needs some OS version logic
# Globals:0
#   None
# Arguments:0
#   None
# Returns:0
#   None
#######################################
set_startup() {
  # enable boot-start, set to run as user splunk
  echo "accepting licensing"
  if [[ $EL_VERSION == 6 ]]; then
    /opt/splunkforwarder/bin/splunk enable boot-start --accept-license --answer-yes --no-prompt; elif
  [[ $EL_VERSION == 7 ]]; then
    /opt/splunkforwarder/bin/splunk enable boot-start --accept-license --answer-yes --no-prompt
  fi
}


#######################################
# set_security
# Kill rest endpoint, set permissions and set a random password
# Globals:0
#   None
# Arguments:0
#   None
# Returns:0
#   None
#######################################
set_security() {
  # disable management port
  echo "disable management port"
  mkdir -p /opt/splunkforwarder/etc/apps/UF-TA-killrest/local
  echo '[httpServer]
  disableDefaultPort = true' > /opt/splunkforwarder/etc/apps/UF-TA-killrest/local/server.conf

  # ensure splunk home is owned by splunk, except for splunk-launch.conf
  echo "permissions fixes"
  chown -R splunk:splunk /opt/splunkforwarder
  chown root:splunk /opt/splunkforwarder/etc/splunk-launch.conf
  chmod 644 /opt/splunkforwarder/etc/splunk-launch.conf

  # change admin pass
  echo "change admin pass"
  echo '[user_info]
  USERNAME = admin
  PASSWORD = changeme' >> /opt/splunkforwarder/etc/system/local/user-seed.conf
  /opt/splunkforwarder/bin/splunk start --accept-license --answer-yes --no-prompt
  /opt/splunkforwarder/bin/splunk edit user admin -password `head -c 500 /dev/urandom | sha256sum | base64 | head -c 16 ; echo` -auth admin:changeme
}

#######################################
# set_syslog
# Set syslog files readable by Splunk user
# Globals:0
#   None
# Arguments:0
#   None
# Returns:0
#   None
#######################################
set_syslog() {
  # ensure user splunk can read /var/log
  setfacl -Rm u:splunk:r-x,d:u:splunk:r-x /var/log

  # do the same for the audit log
  sed -i 's/log_group = root/log_group = splunk/g' /etc/audit/auditd.conf
  chgrp -R splunk /var/log/audit
  chmod 0750 /var/log/audit
  chmod 0640 /var/log/audit/*
}

#######################################
# set_deployclient
# Check into deployment server with DNS
# Globals:0
#   None
# Arguments:0
#   None
# Returns:0
#   None
#######################################
set_deployclient() {
  # set deploymentclientclient, company_deployclient_ta should delete this
  echo '  [deployment-client]
    phoneHomeIntervalInSecs = 60
    [target-broker:deploymentServer]
      targetUri = mydeploymentserver:8089' > /opt/splunkforwarder/etc/system/local/deploymentclient.conf
}

#######################################
# start_splunk
# Starts Splunk, needs some OS logic here
# Globals:0
#   None
# Arguments:0
#   None
# Returns:0
#   None
#######################################
start_splunk() {
  informational "status=restart splunk"
  /etc/init.d/splunk stop
  /etc/init.d/splunk start
  systemctl stop splunk
  systemctl start splunk
}

#######################################
# close
# Logs runtime and exits script
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
close() {
  sleep 10
  service splunk start
  sleep 60
  service splunk stop
  sleep 10
  /etc/init.d/splunk start
  intEnd=`date +%s`
  intRuntime=$((intEnd-intStart))
  informational "app=$strThisFile status=stopped run time was duration=$intRuntime seconds. Wait 2-3 minutes for checkin with deployment server."
  ps -ef | grep -i splunk
}

main() {
# informational "Starting Install of Splunk Universal Forwarder"
  start_script
  install_uf
  set_startup
  set_security
  set_syslog
  set_deployclient
  close
}

main
