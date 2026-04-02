#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Jalankan script sebagai ROOT${NC}"
  exit
fi

LOCAL_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}      GENIEACS AUTO INSTALLER v6        ${NC}"
echo -e "${GREEN}      Ubuntu 20 / 22 / 24 Support       ${NC}"
echo -e "${GREEN}========================================${NC}"

read -p "Mulai install? (y/n): " confirm
[ "$confirm" != "y" ] && exit

echo
echo -e "${GREEN}Update repository${NC}"

apt update

#################################################
# Dependencies
#################################################

echo -e "${GREEN}Install dependencies${NC}"

apt install -y curl wget gnupg build-essential python3 make g++ net-tools

#################################################
# Install libssl1.1 (MongoDB dependency)
#################################################

if dpkg -l | grep -q libssl1.1; then
echo -e "${YELLOW}libssl1.1 sudah terinstall, skip${NC}"
else

echo -e "${GREEN}Install libssl1.1 compatibility${NC}"

ARCH=$(dpkg --print-architecture)
cd /tmp

if [ "$ARCH" = "amd64" ]; then
LIBSSL_URL="http://security.debian.org/debian-security/pool/updates/main/o/openssl/libssl1.1_1.1.1w-0+deb11u5_amd64.deb"
else
LIBSSL_URL="http://security.debian.org/debian-security/pool/updates/main/o/openssl/libssl1.1_1.1.1w-0+deb11u5_arm64.deb"
fi

wget -q $LIBSSL_URL -O libssl1.1.deb

if [ -f libssl1.1.deb ]; then
dpkg -i libssl1.1.deb
rm -f libssl1.1.deb
else
echo -e "${RED}Download libssl1.1 gagal${NC}"
exit 1
fi

fi

#################################################
# Install MongoDB 4.4
#################################################

if command -v mongod >/dev/null; then
echo -e "${YELLOW}MongoDB sudah terinstall, skip${NC}"
else

echo -e "${GREEN}Install MongoDB 4.4${NC}"

curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | \
gpg --dearmor -o /usr/share/keyrings/mongodb-server-4.4.gpg

echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" \
| tee /etc/apt/sources.list.d/mongodb-org-4.4.list

apt update
apt install -y mongodb-org

systemctl enable mongod
systemctl start mongod

fi

#################################################
# Disable Transparent Huge Pages (MongoDB)
#################################################

echo never > /sys/kernel/mm/transparent_hugepage/enabled

#################################################
# Install NodeJS
#################################################

if ! command -v node >/dev/null; then

echo -e "${GREEN}Install NodeJS 20 LTS${NC}"

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

else

NODE_MAJOR=$(node -v | cut -d'.' -f1 | tr -d 'v')

if [ "$NODE_MAJOR" -lt 16 ]; then

echo -e "${YELLOW}Upgrade NodeJS${NC}"

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

else

echo -e "${YELLOW}NodeJS sudah terinstall (v$NODE_MAJOR)${NC}"

fi

fi

#################################################
# Install GenieACS
#################################################

if command -v genieacs-cwmp >/dev/null; then
echo -e "${YELLOW}GenieACS sudah terinstall, skip${NC}"
else

echo -e "${GREEN}Install GenieACS 1.2.13${NC}"

npm install -g genieacs@1.2.13

fi

#################################################
# User
#################################################

if ! id "genieacs" &>/dev/null; then
useradd --system --no-create-home --user-group genieacs
fi

mkdir -p /opt/genieacs/ext
mkdir -p /var/log/genieacs

chown -R genieacs:genieacs /opt/genieacs
chown -R genieacs:genieacs /var/log/genieacs

#################################################
# Environment
#################################################

if [ ! -f /opt/genieacs/genieacs.env ]; then

cat <<EOF >/opt/genieacs/genieacs.env
GENIEACS_CWMP_ACCESS_LOG_FILE=/var/log/genieacs/cwmp-access.log
GENIEACS_NBI_ACCESS_LOG_FILE=/var/log/genieacs/nbi-access.log
GENIEACS_FS_ACCESS_LOG_FILE=/var/log/genieacs/fs-access.log
GENIEACS_UI_ACCESS_LOG_FILE=/var/log/genieacs/ui-access.log
GENIEACS_DEBUG_FILE=/var/log/genieacs/debug.yaml
GENIEACS_EXT_DIR=/opt/genieacs/ext
GENIEACS_UI_JWT_SECRET=$(openssl rand -hex 16)
EOF

chmod 600 /opt/genieacs/genieacs.env

fi

#################################################
# Create Services
#################################################

create_service () {

SERVICE=$1

cat <<EOF >/etc/systemd/system/genieacs-$SERVICE.service
[Unit]
Description=GenieACS $SERVICE
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/bin/genieacs-$SERVICE
Restart=always

[Install]
WantedBy=multi-user.target
EOF

}

create_service cwmp
create_service nbi
create_service fs
create_service ui

#################################################
# Start Services
#################################################

systemctl daemon-reload
systemctl enable genieacs-{cwmp,nbi,fs,ui}
systemctl restart genieacs-{cwmp,nbi,fs,ui}

echo
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN} INSTALL GENIEACS SELESAI ${NC}"
echo -e "${GREEN}================================${NC}"

echo
echo -e "GenieACS UI:"
echo -e "${GREEN}http://$LOCAL_IP:3000${NC}"

echo
echo -e "CWMP URL:"
echo -e "${GREEN}http://$LOCAL_IP:7547${NC}"
