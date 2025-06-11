#!/bin/bash

# این اسکریپت برای اجرا با کاربر root طراحی شده است که در Alpine معمول است.
# اگر با کاربر دیگری اجرا می‌کنید، مطمئن شوید که دسترسی sudo دارید و دستورات را با sudo اجرا کنید.

# نمایش پیام خوش‌آمدگویی و اطلاعات اولیه
echo "================================================="
echo "   IoT Server Initial Setup Script for Alpine    "
echo "================================================="
echo "This script will install all necessary components and configure your server."
echo ""

# مرحله ۱: به‌روزرسانی سیستم و نصب پیش‌نیازهای اصلی
echo "--> Step 1 of 8: Updating system and installing dependencies..."
apk update
# نصب bash, nodejs, npm, git و curl
apk add bash nodejs npm git curl

# مرحله ۲: نصب مدیر فرآیند PM2 به صورت سراسری
echo "--> Step 2 of 8: Installing PM2 process manager globally..."
npm install -g pm2

# مرحله ۳: نصب کلاینت Cloudflare Tunnel (cloudflared)
echo "--> Step 3 of 8: Installing Cloudflare Tunnel client..."
# دانلود فایل باینری برای معماری amd64 (استاندارد اکثر سرورها)
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
# دادن مجوز اجرا به فایل
chmod +x cloudflared
# انتقال فایل به مسیر استاندارد برای اجرای سراسری
mv cloudflared /usr/local/bin/

# مرحله ۴: دانلود کد اصلی سرور از گیت‌هاب

GITHUB_REPO_URL="https://github.com/A-BP/iot-server-alpine.git"

INSTALL_DIR="/opt/iot-server"
echo "--> Step 4 of 8: Cloning the server code from ${GITHUB_REPO_URL}..."
git clone "${GITHUB_REPO_URL}" "${INSTALL_DIR}"

# مرحله ۵: نصب وابستگی‌های پروژه Node.js
echo "--> Step 5 of 8: Installing Node.js project dependencies..."
cd "${INSTALL_DIR}" && npm install

# مرحله ۶: راه‌اندازی سرور Node.js با PM2
echo "--> Step 6 of 8: Starting the Node.js application with PM2..."
cd "${INSTALL_DIR}" && pm2 start server.js --name "iot-app"

# مرحله ۷: اجرای اسکریپت دوم برای ایجاد اولین URI
echo "--> Step 7 of 8: Generating the first URI..."
# ابتدا اسکریپت را قابل اجرا می‌کنیم
chmod +x "${INSTALL_DIR}/get-new-uri-alpine.sh"
# سپس آن را اجرا می‌کنیم تا اولین URI ساخته و فایل HTML آپدیت شود
"${INSTALL_DIR}/get-new-uri-alpine.sh"

# مرحله ۸: تنظیم PM2 برای راه‌اندازی خودکار در استارتاپ سیستم
echo "--> Step 8 of 8: Configuring PM2 to run on system startup..."
pm2 save
# این دستور اسکریپت استارتاپ برای OpenRC (سیستم پیش‌فرض Alpine) تولید می‌کند
# فرض بر این است که با کاربر root اجرا می‌شود
pm2 startup openrc -u root --hp /root

echo ""
echo "✅✅✅ Initial Setup Is Complete! ✅✅✅"
echo "Your server and tunnel are now running and will restart automatically on boot."