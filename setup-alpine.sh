#!/bin/bash
# 'set -e' باعث می‌شود اسکریپت با اولین خطا متوقف شود
set -e

# نمایش پیام خوش‌آمدگویی و اطلاعات اولیه
echo "================================================="
echo "   IoT Server Initial Setup Script for Alpine (v3) "
echo "================================================="
echo "NOTE: This script should be run as the 'root' user."
echo ""

# مرحله ۱: به‌روزرسانی سیستم و نصب پیش‌نیازهای صحیح
echo "--> Step 1 of 8: Updating system and installing dependencies..."
apk update
# در این نسخه، nodejs و npm را به صورت صریح درخواست می‌کنیم
apk add bash nodejs npm git curl

# --- تغییر کلیدی برای حل مشکل command not found ---
# این دستور به شل می‌گوید تا دستورات جدید نصب شده را دوباره شناسایی کند
hash -r
# ----------------------------------------------------

# مرحله ۲: نصب PM2
echo "--> Step 2 of 8: Installing PM2 process manager globally..."
# حالا npm باید بدون مشکل اجرا شود
npm install -g pm2

# مرحله ۳: نصب Cloudflare Tunnel (cloudflared)
echo "--> Step 3 of 8: Installing Cloudflare Tunnel client..."
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
mv cloudflared /usr/local/bin/

# مرحله ۴: دانلود کد اصلی سرور از گیت‌هاب شما
# !! مهم: آدرس گیت‌هاب خود را در خط زیر با آدرس صحیح جایگزین کنید !!
GITHUB_REPO_URL="https://github.com/A-BP/iot-server-alpine.git"
INSTALL_DIR="/opt/iot-server"
echo "--> Step 4 of 8: Cloning the server code from ${GITHUB_REPO_URL}..."
# قبل از کلون کردن، پوشه قبلی (اگر وجود دارد) را پاک می‌کنیم تا از خطا جلوگیری شود
rm -rf "${INSTALL_DIR}"
git clone "${GITHUB_REPO_URL}" "${INSTALL_DIR}"

# بررسی اینکه آیا git clone موفقیت‌آمیز بوده است یا خیر
if [ ! -d "${INSTALL_DIR}" ]; then
    echo "❌ CRITICAL ERROR: Failed to clone the GitHub repository."
    echo "Please check the URL in the script and your internet connection."
    exit 1
fi

# مرحله ۵: نصب وابستگی‌های پروژه Node.js
echo "--> Step 5 of 8: Installing Node.js project dependencies..."
cd "${INSTALL_DIR}" && npm install

# مرحله ۶: راه‌اندازی سرور Node.js با PM2
echo "--> Step 6 of 8: Starting the Node.js application with PM2..."
cd "${INSTALL_DIR}" && pm2 start server.js --name "iot-app"

# مرحله ۷: اجرای اسکریپت دوم برای ایجاد اولین URI
echo "--> Step 7 of 8: Generating the first URI..."
chmod +x "${INSTALL_DIR}/get-new-uri-alpine.sh"
"${INSTALL_DIR}/get-new-uri-alpine.sh"

# مرحله ۸: تنظیم PM2 برای اجرا در استارتاپ سیستم
echo "--> Step 8 of 8: Configuring PM2 to run on system startup..."
pm2 save
pm2 startup openrc -u root --hp /root

echo ""
echo "✅✅✅ Initial Setup Is Complete! ✅✅✅"
echo "Your server and tunnel are now running and will restart automatically on boot."