#!/bin/bash
# code from here https://github.com/MattUebel/splunk_UF_hardening/blob/master/linux/linux_uf.sh

# ensure user splunk can read /var/log
setfacl -Rm u:splunk:r-x,d:u:splunk:r-x /var/log

# do the same for the audit log
sed -i 's/log_group = root/log_group = splunk/g' /etc/audit/auditd.conf
chgrp -R splunk /var/log/audit
chmod 0750 /var/log/audit
chmod 0640 /var/log/audit/*

