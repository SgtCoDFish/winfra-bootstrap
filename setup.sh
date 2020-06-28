#! /usr/bin/env bash

set -eu -o pipefail

if [[ $EUID -ne 0 ]]; then
	echo "must be run as root"
	exit 1
fi

if [ $# -ne 4 ]; then
	echo "USAGE: $0 <hostname> <username> <static-ip> <router-ip>"
	echo "e.g. $0 mypi myuser 192.168.0.100 192.168.0.1"
	exit 1
fi

NEWHOSTNAME="$1"
NEWUSER="$2"
STATICIP="$3"
ROUTERIP="$4"

# note that this will send requests to google/cloudflare - if that's unacceptable you'll need
# to change these values to use different DNS servers
DNSSERVERS="8.8.8.8 8.8.4.4 1.1.1.1"

# force a new password for "pi"
echo "changing password for user 'pi'"
passwd pi

# servers always want UTC, and we'll want to use NTP

timedatectl set-timezone UTC
timedatectl set-ntp true

# disabling automatic updates obviously has security implications, so it's not done by default here

# systemctl stop apt-daily.timer
# systemctl stop apt-daily.service
# systemctl disable apt-daily.timer
# systemctl disable apt-daily.service

# we don't need wpa_supplicant on a wired Pi
systemctl stop wpa_supplicant
systemctl disable wpa_supplicant

# triggerhappy isn't useful on a headless system
systemctl stop triggerhappy.socket
systemctl stop triggerhappy.service
systemctl disable triggerhappy.socket
systemctl disable triggerhappy.service

apt-get remove -y --purge triggerhappy

# create our new user

adduser --gecos "" $NEWUSER
mkdir -p /home/$NEWUSER/.ssh
chown -R $NEWUSER:$NEWUSER /home/$NEWUSER/.ssh
cp /etc/winfra-bootstrap/authorized_keys /home/$NEWUSER/.ssh/authorized_keys

# allow the new user to use sudo without entering a password

echo "$NEWUSER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/100-$NEWUSER-nopasswd

# change the hostname

hostname $NEWHOSTNAME
echo $NEWHOSTNAME > /etc/hostname
sed -i "s/raspberrypi/$NEWHOSTNAME" /etc/hosts

cat << EOF > /etc/ssh/sshd_config
# Different port by default to stop naive attacks
Port 5441

# HostKeys in order of preference
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_rsa_key

# Modern ciphers
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr

# Modern key exchange algorithms
KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256

# Only allow modern MACs
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com

# Root login presents an audit risk
PermitRootLogin no

# Disable password auto, allow only pubkey
PubkeyAuthentication yes
PasswordAuthentication no
UsePAM yes
ChallengeResponseAuthentication no

UseDNS no
PrintMotd no
X11Forwarding no
AcceptEnv LANG LC_*
Subsystem sftp	/usr/lib/openssh/sftp-server
ClientAliveInterval 120
EOF

# Clear out weak DH moduli
awk '$5 >= 3071' /etc/ssh/moduli > /etc/ssh/moduli.tmp && mv /etc/ssh/moduli.tmp /etc/ssh/moduli

# add a script for the new user to clean out "pi"

cat << EOF > /home/$NEWUSER/newuser.sh
#!/usr/bin/env bash

set -eu -o pipefail

if [[ \$EUID -ne 0 ]]; then
	echo "must be run as root"
	exit 1
fi

deluser --remove-home pi
EOF

chown $NEWUSER:$NEWUSER /home/$NEWUSER/newuser.sh
chmod +x /home/$NEWUSER/newuser.sh

# When booted, request a static IP from the router provided
cat << EOF >> /etc/dhcpcd.conf

interface eth0
static ip_address=$STATICIP
static routers=$ROUTERIP
static domain_name_servers=$DNSSERVERS
EOF

systemctl enable ssh
systemctl restart ssh
