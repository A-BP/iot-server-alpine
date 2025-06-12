#!/bin/bash
set -e

echo "====================================================="
echo "   IoT Server Initial Setup Script for Alpine (v6)   "
echo "====================================================="
echo "NOTE: This script should be run as the 'root' user."
echo ""

echo "--> Step 1 of 9: Enabling the 'community' repository..."
sed -i -e 's/^#\(.*\/community\)$/\1/' /etc/apk/repositories

echo "--> Step 2 of 9: Updating package lists..."
apk update

echo "--> Step 3 of 9: Installing all dependencies..."
apk add bash nodejs npm git curl

echo "--> Step 4 of 9: Installing PM2..."
npm install -g pm2

echo "--> Step 5 of 9: Installing Cloudflare Tunnel..."
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
mv cloudflared /usr/local/bin/

# !! مهم: آدرس گیت‌هاب خود را در خط زیر با آدرس صحیح جایگزین کنید !!
GITHUB_REPO_URL="https://github.com/A-BP/iot-server-alpine.git"
INSTALL_DIR="/opt/iot-server"
echo "--> Step 6 of 9: Cloning the server code from ${GITHUB_REPO_URL}..."
rm -rf "${INSTALL_DIR}"
git clone "${GITHUB_REPO_URL}" "${INSTALL_DIR}"

if [ ! -d "${INSTALL_DIR}" ]; then
    echo "❌ CRITICAL ERROR: Failed to clone the GitHub repository."
    exit 1
fi

echo "--> Step 7 of 9: Installing Node.js project dependencies..."
cd "${INSTALL_DIR}" && npm install

echo "--> Step 8 of 9: Starting services and generating the first URI..."
cd "${INSTALL_DIR}"
pm2 start server.js --name "iot-app"
chmod +x get-new-uri-alpine.sh
./get-new-uri-alpine.sh

echo "--> Step 9 of 9: Configuring PM2 to run on system startup..."
pm2 save
pm2 startup openrc -u root --hp /root

echo ""
echo "✅✅✅ Initial Setup Is Complete! ✅✅✅"