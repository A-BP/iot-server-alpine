#!/bin/bash
# 'set -e' باعث می‌شود اسکریپت با اولین خطا متوقف شود
set -e

echo "================================================="
echo "   IoT Server Initial Setup Script for Alpine (v4) "
echo "================================================="
echo "NOTE: This script should be run as the 'root' user."
echo ""

# مرحله ۱: نصب پیش‌نیازها
echo "--> Step 1 of 8: Updating system and installing dependencies..."
apk update
# فقط nodejs را نصب می‌کنیم که npm را به همراه دارد
apk add nodejs git curl bash

# --- تغییر کلیدی برای حل مشکل command not found ---
echo "--> Reloading environment to recognize new commands..."
# این دستور پروفایل سیستم را دوباره بارگذاری می‌کند تا npm و node شناسایی شوند
source /etc/profile
# ----------------------------------------------------

# مرحله ۲: بررسی و نصب PM2
echo "--> Step 2 of 8: Installing PM2 process manager globally..."
# ابتدا بررسی می‌کنیم که آیا npm در دسترس است یا خیر
if ! command -v npm &> /dev/null; then
    echo "❌ CRITICAL ERROR: 'npm' command not found after installing Node.js."
    exit 1
fi
# حالا PM2 را نصب می‌کنیم
npm install -g pm2

# مرحله ۳: نصب Cloudflare Tunnel
echo "--> Step 3 of 8: Installing Cloudflare Tunnel client..."
# ابتدا بررسی می‌کنیم که آیا pm2 در دسترس است یا خیر
if ! command -v pm2 &> /dev/null; then
    echo "❌ CRITICAL ERROR: 'pm2' command not found after installation."
    exit 1
fi
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
mv cloudflared /usr/local/bin/

# مرحله ۴: دانلود کد سرور از گیت‌هاب
# !! مهم: آدرس گیت‌هاب خود را در خط زیر با آدرس صحیح جایگزین کنید !!
GITHUB_REPO_URL="https://github.com/A-BP/iot-server-alpine.git"
INSTALL_DIR="/opt/iot-server"
echo "--> Step 4 of 8: Cloning the server code from ${GITHUB_REPO_URL}..."
rm -rf "${INSTALL_DIR}"
git clone "${GITHUB_REPO_URL}" "${INSTALL_DIR}"

if [ ! -d "${INSTALL_DIR}" ]; then
    echo "❌ CRITICAL ERROR: Failed to clone the GitHub repository."
    exit 1
fi

# مرحله ۵: نصب وابستگی‌های پروژه
echo "--> Step 5 of 8: Installing Node.js project dependencies..."
cd "${INSTALL_DIR}" && npm install

# مرحله ۶: راه‌اندازی سرور Node.js
echo "--> Step 6 of 8: Starting the Node.js application with PM2..."
cd "${INSTALL_DIR}" && pm2 start server.js --name "iot-app"

# مرحله ۷: اجرای اسکریپت دریافت URI
echo "--> Step 7 of 8: Generating the first URI..."
chmod +x "${INSTALL_DIR}/get-new-uri-alpine.sh"
"${INSTALL_DIR}/get-new-uri-alpine.sh"

# مرحله ۸: تنظیم PM2 برای استارتاپ
echo "--> Step 8 of 8: Configuring PM2 to run on system startup..."
pm2 save
pm2 startup openrc -u root --hp /root

echo ""
echo "✅✅✅ Initial Setup Is Complete! ✅✅✅"
echo "Your server and tunnel are now running and will restart automatically on boot."