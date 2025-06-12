#!/bin/bash
set -e

echo "====================================================="
echo "   IoT Server Initial Setup Script for Alpine (v7)   "
echo "====================================================="

# نصب تمام پیش‌نیازها
echo "--> Enabling 'community' repository and updating..."
sed -i -e 's/^#\(.*\/community\)$/\1/' /etc/apk/repositories
apk update
echo "--> Installing dependencies..."
apk add bash nodejs npm git curl

# نصب PM2
echo "--> Installing PM2..."
npm install -g pm2

# نصب Cloudflared
echo "--> Installing Cloudflare Tunnel..."
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
mv cloudflared /usr/local/bin/

# دانلود کد از گیت‌هاب
# !! مهم: آدرس گیت‌هاب خود را در خط زیر با آدرس صحیح جایگزین کنید !!
GITHUB_REPO_URL="https://github.com/A-BP/iot-server-alpine.git"
INSTALL_DIR="/opt/iot-server"
echo "--> Cloning server code from GitHub..."
rm -rf "${INSTALL_DIR}"
git clone "${GITHUB_REPO_URL}" "${INSTALL_DIR}"
if [ ! -d "${INSTALL_DIR}" ]; then echo "❌ ERROR: Failed to clone repository."; exit 1; fi

# نصب وابستگی‌های Node.js
echo "--> Installing Node.js dependencies..."
cd "${INSTALL_DIR}" && npm install

# راه‌اندازی فقط سرور Node.js با PM2
echo "--> Starting Node.js application with PM2..."
cd "${INSTALL_DIR}"
pm2 delete iot-app > /dev/null 2>&1 || true
pm2 start server.js --name "iot-app"

# اجرای اسکریپت دوم برای ایجاد تونل
echo "--> Generating the first URI..."
chmod +x get-new-uri-alpine.sh
./get-new-uri-alpine.sh

# تنظیم PM2 برای استارتاپ (فقط برای iot-app)
echo "--> Configuring Node.js app to run on system startup..."
pm2 save
pm2 startup openrc -u root --hp /root

echo ""
echo "✅✅✅ Initial Setup Is Complete! ✅✅✅"