#!/bin/bash
# MP2 - Linux Server Hardening Script
# Parties 3 + 4 + 5: SSH, UFW, Apache, MariaDB, OpenLDAP, fail2ban, rkhunter, aide, backup
# Run as root on each Debian server

set -e
LOGFILE="/var/log/harden_mp2.log"
exec > >(tee -a $LOGFILE) 2>&1

echo "=========================================="
echo " MOBITECH MP2 - Server Hardening"
echo " $(date)"
echo "=========================================="

# ── Partie 3.1 — System hardening ────────────────────────────────────────────
echo "[3.1] System update and minimal services..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -q && apt-get upgrade -y -q

# Auto security updates
apt-get install -y unattended-upgrades apt-listchanges
dpkg-reconfigure -f noninteractive unattended-upgrades

# Disable useless services
for svc in cups avahi-daemon bluetooth ModemManager; do
    systemctl stop $svc 2>/dev/null || true
    systemctl disable $svc 2>/dev/null || true
done

# Timezone + NTP
timedatectl set-timezone Africa/Casablanca
apt-get install -y chrony
systemctl enable chrony && systemctl start chrony

# ── Partie 3.2 — SSH hardening ────────────────────────────────────────────────
echo "[3.2] SSH hardening..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat > /etc/ssh/sshd_config << 'EOF'
Port 2222
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication
PermitRootLogin no
MaxAuthTries 3
MaxSessions 5
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication yes

# MFA (Google Authenticator)
AuthenticationMethods publickey,keyboard-interactive

# Restrictions
AllowUsers adminit
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
PrintMotd no
Banner /etc/ssh/banner

# VLAN30 Admin only (192.168.30.0/24)
# AllowUsers restricted via PAM/firewall

# Logging
SyslogFacility AUTH
UsePAM yes
LogLevel VERBOSE
EOF

# SSH banner
cat > /etc/ssh/banner << 'EOF'
*******************************************************************
*   MOBITECH - Systeme Informatique Prive                        *
*   Acces non autorise strictement interdit                      *
*   Toute connexion est enregistree et surveillee                *
*******************************************************************
EOF

# Generate admin SSH key pair if not exists
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -C "adminit@mobitech"
fi

systemctl restart ssh

# ── Partie 3.3 — UFW Firewall ─────────────────────────────────────────────────
echo "[3.3] UFW firewall..."
apt-get install -y ufw

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH on custom port - VLAN30 admin only
ufw allow from 192.168.30.0/24 to any port 2222 proto tcp comment "SSH Admin VLAN30"

# HTTP/HTTPS (for web server)
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"

# LDAP (for AD-LDAP server)
ufw allow from 192.168.10.0/24 to any port 389 proto tcp comment "LDAP internal"
ufw allow from 192.168.10.0/24 to any port 636 proto tcp comment "LDAPS internal"

# MariaDB (VLAN10 only)
ufw allow from 192.168.10.0/24 to any port 3306 proto tcp comment "MariaDB VLAN10"
ufw allow from 192.168.20.0/24 to any port 3306 proto tcp comment "MariaDB VLAN20"

# Block excessive ICMP
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 5 -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

ufw --force enable
ufw status verbose

# ── Partie 3.4 — Apache hardening ────────────────────────────────────────────
echo "[3.4] Apache/Nginx hardening..."
apt-get install -y apache2 openssl

# Disable unnecessary modules
a2dismod status autoindex -f 2>/dev/null || true
a2enmod ssl headers rewrite

# Hide server banner
cat >> /etc/apache2/conf-enabled/security.conf << 'EOF'
ServerTokens Prod
ServerSignature Off
TraceEnable Off
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
Header always set X-XSS-Protection "1; mode=block"
EOF

# Self-signed SSL certificate
mkdir -p /etc/apache2/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/apache2/ssl/mobitech.key \
    -out /etc/apache2/ssl/mobitech.crt \
    -subj "/C=MA/ST=Tanger/L=Tanger/O=MOBITECH/CN=mobitech.local"

# Enable HTTPS vhost
cat > /etc/apache2/sites-available/mobitech-ssl.conf << 'EOF'
<VirtualHost *:443>
    ServerName mobitech.local
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl/mobitech.crt
    SSLCertificateKeyFile /etc/apache2/ssl/mobitech.key
    SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite HIGH:!aNULL:!MD5
</VirtualHost>
<VirtualHost *:80>
    ServerName mobitech.local
    Redirect permanent / https://mobitech.local/
</VirtualHost>
EOF

a2ensite mobitech-ssl
systemctl restart apache2

# ── Partie 3.4 — MariaDB hardening ───────────────────────────────────────────
echo "[3.4] MariaDB hardening..."
apt-get install -y mariadb-server

# Secure installation equivalent
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'Mobitech2024!';"
mysql -e "FLUSH PRIVILEGES;"

# Restrict network binding to VLAN10 only
sed -i 's/^bind-address.*/bind-address = 192.168.10.30/' /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl restart mariadb

# ── Partie 4.1 — OpenLDAP ────────────────────────────────────────────────────
echo "[4.1] OpenLDAP installation..."
LDAP_PASS="Mobitech2024!"
LDAP_DOMAIN="dc=mobitech,dc=local"

debconf-set-selections << EOF
slapd slapd/internal/generated_adminpw password $LDAP_PASS
slapd slapd/internal/adminpw password $LDAP_PASS
slapd slapd/password2 password $LDAP_PASS
slapd slapd/password1 password $LDAP_PASS
slapd slapd/domain string mobitech.local
slapd shared/organization string MOBITECH
slapd slapd/backend string MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
EOF

apt-get install -y slapd ldap-utils
dpkg-reconfigure -f noninteractive slapd

# Create OUs: Direction, RH, IT, Commercial
cat > /tmp/mobitech_ou.ldif << EOF
dn: ou=Direction,$LDAP_DOMAIN
objectClass: organizationalUnit
ou: Direction

dn: ou=RH,$LDAP_DOMAIN
objectClass: organizationalUnit
ou: RH

dn: ou=IT,$LDAP_DOMAIN
objectClass: organizationalUnit
ou: IT

dn: ou=Commercial,$LDAP_DOMAIN
objectClass: organizationalUnit
ou: Commercial
EOF

ldapadd -x -D "cn=admin,$LDAP_DOMAIN" -w "$LDAP_PASS" -f /tmp/mobitech_ou.ldif

# Create sample users per OU
cat > /tmp/mobitech_users.ldif << EOF
dn: uid=adminit,ou=IT,$LDAP_DOMAIN
objectClass: inetOrgPerson
objectClass: posixAccount
uid: adminit
cn: Admin IT
sn: IT
uidNumber: 2000
gidNumber: 2000
homeDirectory: /home/adminit
loginShell: /bin/bash
userPassword: $(slappasswd -s "Mobitech2024!")

dn: uid=directeur,ou=Direction,$LDAP_DOMAIN
objectClass: inetOrgPerson
objectClass: posixAccount
uid: directeur
cn: Directeur General
sn: General
uidNumber: 2001
gidNumber: 2001
homeDirectory: /home/directeur
loginShell: /bin/bash
userPassword: $(slappasswd -s "Mobitech2024!")
EOF

ldapadd -x -D "cn=admin,$LDAP_DOMAIN" -w "$LDAP_PASS" -f /tmp/mobitech_users.ldif

# ── Partie 4.2 — Password policy + MFA ───────────────────────────────────────
echo "[4.2] Password policy and MFA..."
apt-get install -y libpam-pwquality libpam-google-authenticator

# pam_pwquality config
cat > /etc/security/pwquality.conf << 'EOF'
minlen = 12
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
remember = 12
maxrepeat = 3
EOF

# PAM SSH with Google Authenticator
cat > /etc/pam.d/sshd << 'EOF'
auth required pam_google_authenticator.so nullok
auth required pam_permit.so
@include common-account
@include common-session
@include common-password
session required pam_limits.so
EOF

# Limit simultaneous connections per user
echo "* hard maxlogins 3" >> /etc/security/limits.conf

# ── Partie 4.3 — Sudo granulaire ─────────────────────────────────────────────
echo "[4.3] Sudo configuration..."
apt-get install -y sudo

# Remove unused system accounts
for user in games news uucp proxy list irc gnats; do
    userdel $user 2>/dev/null || true
done

# Granular sudo
cat > /etc/sudoers.d/mobitech << 'EOF'
# IT group - full sudo
%it ALL=(ALL:ALL) ALL

# Operators - service management only
%operators ALL=(ALL) NOPASSWD: /bin/systemctl restart *, /bin/systemctl status *

# Log all sudo
Defaults logfile=/var/log/sudo.log
Defaults log_input, log_output
EOF

chmod 440 /etc/sudoers.d/mobitech

# ── Partie 5.1 — Centralized logging ─────────────────────────────────────────
echo "[5.1] rsyslog configuration..."
apt-get install -y rsyslog

cat >> /etc/rsyslog.conf << 'EOF'

# Send all logs to central syslog server (AD-LDAP 192.168.10.10)
*.* @192.168.10.10:514

# Local logging with rotation
$FileOwner root
$FileGroup adm
$FileCreateMode 0640
$DirCreateMode 0755
EOF

systemctl restart rsyslog

# ── Partie 5.2 — fail2ban ────────────────────────────────────────────────────
echo "[5.2] fail2ban configuration..."
apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 86400
findtime = 600
maxretry = 5
backend  = systemd
destemail = admin@mobitech.local
sendername = fail2ban
action = %(action_mwl)s

[sshd]
enabled  = true
port     = 2222
logpath  = %(sshd_log)s
maxretry = 5
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd

[apache-auth]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 5

[apache-badbots]
enabled  = true
port     = http,https
logpath  = %(apache_access_log)s
maxretry = 2

[pure-ftpd]
enabled  = true
port     = ftp,ftp-data,ftps,ftps-data
logpath  = /var/log/syslog
maxretry = 5
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# ── Partie 5.3 — rkhunter + aide ─────────────────────────────────────────────
echo "[5.3] rkhunter and aide..."
apt-get install -y rkhunter aide

# rkhunter config
sed -i 's/UPDATE_MIRRORS=0/UPDATE_MIRRORS=1/' /etc/rkhunter.conf
sed -i 's/MIRRORS_MODE=1/MIRRORS_MODE=0/' /etc/rkhunter.conf
rkhunter --update --quiet || true
rkhunter --propupd --quiet

# aide baseline
aideinit
cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Weekly cron jobs
cat > /etc/cron.weekly/security-scan << 'EOF'
#!/bin/bash
rkhunter --check --skip-keypress --report-warnings-only | mail -s "rkhunter report $(hostname)" admin@mobitech.local
aide --check | mail -s "aide integrity report $(hostname)" admin@mobitech.local
EOF
chmod +x /etc/cron.weekly/security-scan

# ── Partie 5.4 — Encrypted backup ────────────────────────────────────────────
echo "[5.4] Encrypted backup setup..."
apt-get install -y gnupg rsync

# GPG key for backup encryption
gpg --batch --gen-key << 'EOF'
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: MOBITECH Backup
Name-Email: backup@mobitech.local
Expire-Date: 0
%no-passphrase
%commit
EOF

mkdir -p /backup/daily /backup/weekly

cat > /usr/local/bin/backup_mobitech.sh << 'BACKUP'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/daily"
DEST="$BACKUP_DIR/backup_$DATE"

# Incremental rsync
rsync -az --delete /etc /var/log /home "$DEST/"

# Encrypt with GPG
tar -czf - "$DEST" | gpg --symmetric --cipher-algo AES256 \
    --passphrase "MobitechBackup2024!" --batch \
    -o "$BACKUP_DIR/backup_$DATE.tar.gz.gpg"

rm -rf "$DEST"

# Keep only last 7 days
find "$BACKUP_DIR" -name "*.gpg" -mtime +7 -delete

echo "Backup completed: $DATE"
BACKUP

chmod +x /usr/local/bin/backup_mobitech.sh

# Daily backup cron
echo "0 2 * * * root /usr/local/bin/backup_mobitech.sh >> /var/log/backup.log 2>&1" \
    > /etc/cron.d/mobitech-backup

echo ""
echo "=========================================="
echo " Hardening COMPLETE"
echo " $(date)"
echo "=========================================="
echo ""
echo "Summary:"
echo "  SSH port   : 2222 (key auth only, VLAN30)"
echo "  UFW        : active - deny all incoming by default"
echo "  Apache     : HTTPS only, banner hidden"
echo "  MariaDB    : secured, bound to 192.168.10.30"
echo "  OpenLDAP   : mobitech.local, OUs created"
echo "  fail2ban   : 5 attempts / 24h ban"
echo "  rkhunter   : weekly scan scheduled"
echo "  aide       : baseline created, weekly check"
echo "  Backup     : daily encrypted GPG, 7-day retention"
echo ""
echo "IMPORTANT: Run 'google-authenticator' as each user to setup MFA"
echo "IMPORTANT: Add SSH public key to ~/.ssh/authorized_keys before locking password auth"
