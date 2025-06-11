#!/bin/bash

# نمایش پیام خوش‌آمدگویی
echo "================================================="
echo "   IoT Server Initial Setup Script for Alpine    "
echo "================================================="
echo "NOTE: This script should be run as the 'root' user."
echo ""

# مرحله ۱: به‌روزرسانی سیستم و نصب پیش‌نیازها
echo "--> Step 1: Updating system and installing dependencies..."
# apk از sudo استفاده نمی‌کند و معمولا با کاربر root اجرا می‌شود.
apk update
# bash را نصب می‌کنیم تا از سازگاری کامل اسکریپت مطمئن شویم
apk add bash nodejs npm git curl

# مرحله ۲: نصب PM2
echo "--> Step 2: Installing PM2 process manager globally..."
npm install -g pm2

# مرحله ۳: نصب Cloudflare Tunnel (مخصوص Alpine/Linux عمومی)
echo "--> Step 3: Installing Cloudflare Tunnel client..."
# از آنجایی که پکیج .deb وجود ندارد، فایل باینری را مستقیم دانلود می‌کنیم
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
# فایل را به مسیری که در PATH سیستم قرار دارد منتقل می‌کنیم
mv cloudflared /usr/local/bin/

# مرحله ۴: دانلود کد اصلی سرور از گیت‌هاب شما
# مهم: آدرس گیت‌هاب خود را در خط زیر جایگزین کنید!
echo "--> Step 4: Cloning the server code from GitHub..."
git clone https://github.com/A-BP/iot-server-alpine.git /opt/iot-server

# مرحله ۵: نصب وابستگی‌های Node.js
echo "--> Step 5: Installing Node.js dependencies..."
cd /opt/iot-server && npm install

# مرحله ۶: راه‌اندازی سرور Node.js با PM2
echo "--> Step 6: Starting the Node.js server with PM2..."
cd /opt/iot-server && pm2 start server.js --name "iot-app"

# مرحله ۷: راه‌اندازی Quick Tunnel و نمایش URI
echo "--> Step 7: Starting Quick Tunnel and fetching the URI..."
# ابتدا اسکریپت دریافت URI جدید را قابل اجرا می‌کنیم
chmod +x /opt/iot-server/get-new-uri-alpine.sh
# سپس آن را برای اولین بار اجرا می‌کنیم
/opt/iot-server/get-new-uri-alpine.sh

# مرحله ۸: تنظیم PM2 برای اجرا در استارتاپ (مخصوص Alpine با OpenRC)
echo "--> Step 8: Configuring PM2 to run on startup..."
pm2 save
# این دستور اسکریپت استارتاپ برای OpenRC (سیستم init پیش‌فرض Alpine) تولید می‌کند
pm2 startup openrc -u root --hp /root

echo ""
echo "✅ Initial setup is complete."