#!/bin/bash
# MP2 - Hardening continuation for AD-LDAP server
# Picks up from [3.4] MariaDB (after apt install succeeded but mysql commands failed)
# Runs: MariaDB fix + [4.1] OpenLDAP + [4.2] PAM + [4.3] sudo + [5.1-5.4]

set -e
LOGFILE="/var/log/harden_mp2.log"
exec > >(tee -a $LOGFILE) 2>&1

echo "=========================================="
echo " MOBITECH MP2 - Hardening Continuation"
echo " $(date)"
echo "=========================================="

export DEBIAN_FRONTEND=noninteractive

# ── [3.4] MariaDB hardening (fix: use mysql with unix_socket) ─────────────────
echo "[3.4] MariaDB hardening (fix)..."

# Ensure MariaDB is running
systemctl start mariadb
sleep 2

# On Debian 12, MariaDB root uses unix_socket — run as system root without -p
mariadb -u root -e "DELETE FROM mysql.user WHERE User='';"
mariadb -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');"
mariadb -u root -e "DROP DATABASE IF EXISTS test;"
mariadb -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'Mobitech2024!';"
mariadb -u root -e "FLUSH PRIVILEGES;"

# Restrict binding to VLAN10 (AD-LDAP IP)
sed -i 's/^bind-address.*/bind-address = 192.168.10.10/' /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl restart mariadb
echo "  MariaDB secured OK"

# ── [4.1] OpenLDAP ────────────────────────────────────────────────────────────
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

# Create OUs
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

# Create users
HASH_ADMIN=$(slappasswd -s "Mobitech2024!")
HASH_DIR=$(slappasswd -s "Mobitech2024!")

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
userPassword: $HASH_ADMIN

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
userPassword: $HASH_DIR
EOF

ldapadd -x -D "cn=admin,$LDAP_DOMAIN" -w "$LDAP_PASS" -f /tmp/mobitech_users.ldif
echo "  OpenLDAP: mobitech.local, OUs + users created"

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

# ── [4.3] Sudo configuration ──────────────────────────────────────────────────
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
echo "[5.1] rsyslog configuration..."
apt-get install -y rsyslog

cat >> /etc/rsyslog.conf << 'EOF'

# Send all logs to central syslog server (AD-LDAP 192.168.10.10)
*.* @192.168.10.10:514

$FileOwner root
$FileGroup adm
$FileCreateMode 0640
$DirCreateMode 0755
EOF

systemctl restart rsyslog

# ── [5.2] fail2ban ────────────────────────────────────────────────────────────
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

# ── [5.3] rkhunter + aide ─────────────────────────────────────────────────────
echo "[5.3] rkhunter and aide..."
apt-get install -y rkhunter aide

sed -i 's/UPDATE_MIRRORS=0/UPDATE_MIRRORS=1/' /etc/rkhunter.conf
sed -i 's/MIRRORS_MODE=1/MIRRORS_MODE=0/' /etc/rkhunter.conf
rkhunter --update --quiet || true
rkhunter --propupd --quiet

aideinit
cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

cat > /etc/cron.weekly/security-scan << 'EOF'
#!/bin/bash
rkhunter --check --skip-keypress --report-warnings-only | mail -s "rkhunter report $(hostname)" admin@mobitech.local
aide --check | mail -s "aide integrity report $(hostname)" admin@mobitech.local
EOF
chmod +x /etc/cron.weekly/security-scan

# ── [5.4] Encrypted backup ────────────────────────────────────────────────────
echo "[5.4] Encrypted backup setup..."
apt-get install -y gnupg rsync

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

rsync -az --delete /etc /var/log /home "$DEST/"

tar -czf - "$DEST" | gpg --symmetric --cipher-algo AES256 \
    --passphrase "MobitechBackup2024!" --batch \
    -o "$BACKUP_DIR/backup_$DATE.tar.gz.gpg"

rm -rf "$DEST"
find "$BACKUP_DIR" -name "*.gpg" -mtime +7 -delete
echo "Backup completed: $DATE"
BACKUP

chmod +x /usr/local/bin/backup_mobitech.sh
echo "0 2 * * * root /usr/local/bin/backup_mobitech.sh >> /var/log/backup.log 2>&1" \
    > /etc/cron.d/mobitech-backup

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " Hardening COMPLETE"
echo " $(date)"
echo "=========================================="
echo ""
echo "Summary:"
echo "  SSH port   : 2222 (key auth only, VLAN30)"
echo "  UFW        : active"
echo "  Apache     : HTTPS only"
echo "  MariaDB    : secured, bound to 192.168.10.10"
echo "  OpenLDAP   : mobitech.local, OUs+users created"
echo "  fail2ban   : active"
echo "  rkhunter   : propupd done, weekly scan scheduled"
echo "  aide       : baseline created"
echo "  Backup     : daily GPG cron"
echo ""
echo "NEXT: run 'google-authenticator' as adminit to setup MFA"
echo "NEXT: add SSH public key to ~/.ssh/authorized_keys"
