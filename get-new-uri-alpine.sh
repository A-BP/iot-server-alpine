#!/bin/bash

echo "============================================="
echo "      Get New WSS URI Script for Alpine      "
echo "============================================="

# مسیر نصب پروژه را مشخص می‌کند
INSTALL_DIR="/opt/iot-server"
# مسیر کامل فایل HTML که باید آپدیت شود
HTML_FILE_PATH="${INSTALL_DIR}/public/index.html"

# بررسی می‌کند که آیا PM2 نصب و در دسترس است یا خیر
if ! command -v pm2 &> /dev/null
then
    echo "❌ Error: PM2 is not installed. Please run the main setup script first."
    exit 1
fi

echo "--> Preparing HTML file template..."
# اگر فایل پشتیبان (template) از index.html وجود ندارد، آن را ایجاد می‌کند.
# این کار تضمین می‌کند که ما همیشه یک نسخه اصلی با Placeholder داریم.
if [ ! -f "${HTML_FILE_PATH}.template" ]; then
    cp "$HTML_FILE_PATH" "${HTML_FILE_PATH}.template"
fi
# فایل HTML فعلی را با نسخه اصلی (دارای Placeholder) بازنویسی می‌کنیم
cp "${HTML_FILE_PATH}.template" "$HTML_FILE_PATH"

echo "--> Stopping the old tunnel (if it exists)..."
# فرآیند تونل قبلی را در PM2 حذف می‌کند تا از اجرای همزمان چند تونل جلوگیری شود
pm2 delete cflare-tunnel > /dev/null 2>&1

echo "--> Starting a new tunnel..."
# تونل جدید را با PM2 راه‌اندازی می‌کند
# استفاده از --no-autoupdate از نمایش پیام‌های اضافی در لاگ جلوگیری می‌کند
pm2 start "cloudflared tunnel --no-autoupdate --url http://localhost:8000" --name "cflare-tunnel"

# چند ثانیه صبر می‌کند تا تونل زمان کافی برای راه‌اندازی و تولید لاگ داشته باشد
echo "--> Waiting for tunnel to establish... (approx. 8 seconds)"
sleep 8

echo "--> Fetching the new URI from logs..."
# آدرس URI جدید را از لاگ‌های PM2 با دقت استخراج می‌کند
URI=$(pm2 logs cflare-tunnel --lines 20 | grep -o 'https://[a-z0-9-]*\.trycloudflare.com' | head -n 1)

# بررسی می‌کند که آیا آدرس با موفقیت استخراج شده است یا خیر
if [ -n "$URI" ]; then
    WSS_URI="wss://${URI#https://}"
    
    echo "--> Updating HTML file at ${HTML_FILE_PATH}..."
    # Placeholder را با آدرس جدید در فایل HTML جایگزین می‌کند
    sed -i "s|WSS_URI_PLACEHOLDER|${WSS_URI}|g" "$HTML_FILE_PATH"

    echo ""
    echo "✅ New URI Generated Successfully!"
    echo "=================================================="
    echo "Your HTTP address for browser is: ${URI}"
    echo "Your WSS URI for ESP32 is:      ${WSS_URI}"
    echo "=================================================="
else
    echo "❌ Failed to retrieve a new URI. Please check logs using: pm2 logs cflare-tunnel"
fi

# لاگ‌های PM2 را پاک می‌کند تا در اجرای بعدی تداخلی ایجاد نشود
pm2 flush cflare-tunnel > /dev/null 2>&1