#!/bin/bash
# 'set -e' باعث می‌شود اسکریپت با اولین خطا متوقف شود
set -e

echo "====================================================="
echo "   IoT Server Initial Setup Script for Alpine (v5)   "
echo "====================================================="
echo "NOTE: This script should be run as the 'root' user."
echo ""

# مرحله ۱: فعال‌سازی مخزن Community
echo "--> Step 1 of 9: Enabling the 'community' repository..."
# این دستور خط مربوط به مخزن community را در فایل تنظیمات از حالت کامنت خارج می‌کند
sed -i -e 's/^#\(.*\/community\)$/\1/' /etc/apk/repositories

# مرحله ۲: به‌روزرسانی لیست پکیج‌ها از تمام مخازن
echo "--> Step 2 of 9: Updating package lists from all repositories..."
apk update

# مرحله ۳: نصب تمام پیش‌نیازها
echo "--> Step 3 of 9: Installing all dependencies..."
# حالا که مخزن community فعال است، npm باید پیدا شود
apk add bash nodejs npm git curl

# مرحله ۴: نصب PM2
echo "--> Step 4 of 9: Installing PM2 process manager globally..."
npm install -g pm2

# مرحله ۵: نصب Cloudflare Tunnel
echo "--> Step 5 of 9: Installing Cloudflare Tunnel client..."
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
mv cloudflared /usr/local/bin/

# مرحله ۶: دانلود کد سرور از گیت‌هاب
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

# مرحله ۷: نصب وابستگی‌های پروژه
echo "--> Step 7 of 9: Installing Node.js project dependencies..."
cd "${INSTALL_DIR}" && npm install

# مرحله ۸: راه‌اندازی سرور و تونل
echo "--> Step 8 of 9: Starting services and generating the first URI..."
cd "${INSTALL_DIR}"
pm2 start server.js --name "iot-app"
# اسکریپت دریافت URI را اجرا می‌کنیم
chmod +x get-new-uri-alpine.sh
./get-new-uri-alpine.sh

# مرحله ۹: تنظیم PM2 برای استارتاپ
echo "--> Step 9 of 9: Configuring PM2 to run on system startup..."
pm2 save
pm2 startup openrc -u root --hp /root

echo ""
echo "✅✅✅ Initial Setup Is Complete! ✅✅✅"
echo "Your server and tunnel are now running and will restart automatically on boot."