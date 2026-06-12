#!/bin/bash
# MP2 Hardening - Mail-Server (192.168.50.20, DMZ)
# Covers: SSH, UFW, Postfix+Dovecot, MariaDB, PAM/MFA, sudo, rsyslog, fail2ban, rkhunter, aide, backup
# NO OpenLDAP

set -e
LOGFILE="/var/log/harden_mp2.log"
exec > >(tee -a $LOGFILE) 2>&1
export DEBIAN_FRONTEND=noninteractive
SERVER_IP="192.168.50.20"

echo "=========================================="
echo " MOBITECH MP2 - Hardening: Mail-Server"
echo " $(date)"
echo "=========================================="

# ── [3.1] System update ───────────────────────────────────────────────────────
echo "[3.1] System update..."
apt-get update -q && apt-get upgrade -y -q
apt-get install -y unattended-upgrades apt-listchanges
dpkg-reconfigure -f noninteractive unattended-upgrades
for svc in cups avahi-daemon bluetooth ModemManager; do
    systemctl stop $svc 2>/dev/null || true
    systemctl disable $svc 2>/dev/null || true
done
timedatectl set-timezone Africa/Casablanca
apt-get install -y chrony
systemctl enable chrony && systemctl start chrony

# ── [3.2] SSH hardening ───────────────────────────────────────────────────────
echo "[3.2] SSH hardening..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
cat > /etc/ssh/sshd_config << 'EOF'
Port 2222
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin no
MaxAuthTries 3
MaxSessions 5
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication yes
AuthenticationMethods publickey,keyboard-interactive
AllowUsers adminit
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
PrintMotd no
Banner /etc/ssh/banner
SyslogFacility AUTH
UsePAM yes
LogLevel VERBOSE
EOF

cat > /etc/ssh/banner << 'EOF'
*******************************************************************
*   MOBITECH - Systeme Informatique Prive                        *
*   Acces non autorise strictement interdit                      *
*   Toute connexion est enregistree et surveillee                *
*******************************************************************
EOF

if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -C "adminit@mobitech"
fi
systemctl restart ssh

# ── [3.3] UFW firewall ────────────────────────────────────────────────────────
echo "[3.3] UFW firewall..."
apt-get install -y ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from 192.168.30.0/24 to any port 2222 proto tcp comment "SSH Admin VLAN30"
ufw allow 25/tcp  comment "SMTP"
ufw allow 587/tcp comment "SMTP submission"
ufw allow 993/tcp comment "IMAPS"
ufw allow 143/tcp comment "IMAP"
ufw --force enable
ufw status verbose

# ── [3.4] Postfix + Dovecot (mail stack) ─────────────────────────────────────
echo "[3.4] Mail stack (Postfix + Dovecot)..."
debconf-set-selections << 'EOF'
postfix postfix/main_mailer_type select Internet Site
postfix postfix/mailname string mobitech.local
EOF
apt-get install -y postfix dovecot-core dovecot-imapd openssl

# Postfix hardening
postconf -e "smtpd_banner = \$myhostname ESMTP"
postconf -e "disable_vrfy_command = yes"
postconf -e "smtpd_helo_required = yes"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination"
postconf -e "myhostname = mail.mobitech.local"
postconf -e "mydomain = mobitech.local"
postconf -e "mynetworks = 192.168.10.0/24 192.168.20.0/24 192.168.30.0/24 127.0.0.0/8"

# TLS for Postfix
mkdir -p /etc/postfix/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/postfix/ssl/mail.key \
    -out /etc/postfix/ssl/mail.crt \
    -subj "/C=MA/ST=Tanger/L=Tanger/O=MOBITECH/CN=mail.mobitech.local"

postconf -e "smtpd_tls_cert_file = /etc/postfix/ssl/mail.crt"
postconf -e "smtpd_tls_key_file = /etc/postfix/ssl/mail.key"
postconf -e "smtpd_use_tls = yes"
postconf -e "smtpd_tls_security_level = may"

systemctl restart postfix

# Dovecot minimal config
cat > /etc/dovecot/conf.d/10-ssl.conf << 'EOF'
ssl = yes
ssl_cert = </etc/postfix/ssl/mail.crt
ssl_key = </etc/postfix/ssl/mail.key
ssl_min_protocol = TLSv1.2
EOF
systemctl restart dovecot
echo "  Mail stack configured OK"

# ── [3.4] MariaDB hardening (proactive unix_socket fix) ───────────────────────
echo "[3.4] MariaDB hardening..."
apt-get install -y mariadb-server

systemctl stop mariadb || true
sleep 2
pkill -f mysqld || true
sleep 2
rm -f /run/mysqld/mysqld.pid /run/mysqld/mysqld.sock
mysqld_safe --skip-grant-tables --skip-networking &
MYSQLD_PID=$!
sleep 8
mariadb -e "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket; FLUSH PRIVILEGES;" 2>/dev/null || true
kill $MYSQLD_PID 2>/dev/null || true
wait $MYSQLD_PID 2>/dev/null || true
sleep 3
pkill -f mysqld || true
sleep 2
rm -f /run/mysqld/mysqld.pid /run/mysqld/mysqld.sock
systemctl start mariadb
sleep 3

mariadb -u root -e "DELETE FROM mysql.user WHERE User='';"
mariadb -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');"
mariadb -u root -e "DROP DATABASE IF EXISTS test;"
mariadb -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'Mobitech2024!';"
mariadb -u root -e "FLUSH PRIVILEGES;"
sed -i "s/^bind-address.*/bind-address = 127.0.0.1/" /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl restart mariadb
echo "  MariaDB secured OK"

# ── [4.2] Password policy + MFA ───────────────────────────────────────────────
echo "[4.2] Password policy and MFA..."
apt-get install -y libpam-pwquality libpam-google-authenticator
cat > /etc/security/pwquality.conf << 'EOF'
minlen = 12
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
remember = 12
maxrepeat = 3
EOF

cat > /etc/pam.d/sshd << 'EOF'
auth required pam_google_authenticator.so nullok
auth required pam_permit.so
@include common-account
@include common-session
@include common-password
session required pam_limits.so
EOF

echo "* hard maxlogins 3" >> /etc/security/limits.conf

# ── [4.3] Sudo ────────────────────────────────────────────────────────────────
echo "[4.3] Sudo configuration..."
apt-get install -y sudo
for user in games news uucp proxy list irc gnats; do
    userdel $user 2>/dev/null || true
done
cat > /etc/sudoers.d/mobitech << 'EOF'
%it ALL=(ALL:ALL) ALL
%operators ALL=(ALL) NOPASSWD: /bin/systemctl restart *, /bin/systemctl status *
Defaults logfile=/var/log/sudo.log
Defaults log_input, log_output
EOF
chmod 440 /etc/sudoers.d/mobitech

# ── [5.1] rsyslog ─────────────────────────────────────────────────────────────
echo "[5.1] rsyslog..."
apt-get install -y rsyslog
cat >> /etc/rsyslog.conf << 'EOF'

*.* @192.168.10.10:514
$FileOwner root
$FileGroup adm
$FileCreateMode 0640
$DirCreateMode 0755
EOF
systemctl restart rsyslog

# ── [5.2] fail2ban ────────────────────────────────────────────────────────────
echo "[5.2] fail2ban..."
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

[postfix]
enabled  = true
port     = smtp,465,587
logpath  = %(postfix_log)s
maxretry = 5

[dovecot]
enabled  = true
port     = imap,imaps
logpath  = %(dovecot_log)s
maxretry = 5
EOF
systemctl enable fail2ban
systemctl restart fail2ban

# ── [5.3] rkhunter + aide ─────────────────────────────────────────────────────
echo "[5.3] rkhunter + aide..."
apt-get install -y rkhunter aide || true
sed -i 's/UPDATE_MIRRORS=0/UPDATE_MIRRORS=1/' /etc/rkhunter.conf 2>/dev/null || true
sed -i 's/MIRRORS_MODE=1/MIRRORS_MODE=0/' /etc/rkhunter.conf 2>/dev/null || true
rkhunter --update --quiet || true
rkhunter --propupd --quiet || true
aideinit || true
[ -f /var/lib/aide/aide.db.new ] && cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
cat > /etc/cron.weekly/security-scan << 'EOF'
#!/bin/bash
rkhunter --check --skip-keypress --report-warnings-only | mail -s "rkhunter $(hostname)" admin@mobitech.local
aide --check | mail -s "aide $(hostname)" admin@mobitech.local
EOF
chmod +x /etc/cron.weekly/security-scan

# ── [5.4] Backup ──────────────────────────────────────────────────────────────
echo "[5.4] Encrypted backup..."
apt-get install -y gnupg rsync
mkdir -p /backup/daily /backup/weekly
cat > /usr/local/bin/backup_mobitech.sh << 'BACKUP'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
DEST="/backup/daily/backup_$DATE"
rsync -az --delete /etc /var/log /home "$DEST/"
tar -czf - "$DEST" | gpg --symmetric --cipher-algo AES256 \
    --passphrase "MobitechBackup2024!" --batch \
    -o "/backup/daily/backup_$DATE.tar.gz.gpg"
rm -rf "$DEST"
find /backup/daily -name "*.gpg" -mtime +7 -delete
echo "Backup: $DATE"
BACKUP
chmod +x /usr/local/bin/backup_mobitech.sh
echo "0 2 * * * root /usr/local/bin/backup_mobitech.sh >> /var/log/backup.log 2>&1" \
    > /etc/cron.d/mobitech-backup

echo ""
echo "=========================================="
echo " Hardening COMPLETE: Mail-Server"
echo " $(date)"
echo "=========================================="
echo "  SSH:2222  UFW:active  Postfix+Dovecot:TLS  fail2ban:active"
echo "  NEXT: google-authenticator as adminit"
