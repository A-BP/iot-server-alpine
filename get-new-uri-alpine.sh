#!/bin/bash
echo "--> Attempting to generate a new WSS URI..."

# مسیر فایل HTML را مشخص می‌کند
HTML_FILE_PATH="/opt/iot-server/public/index.html" # فرض می‌کنیم فایل index.html شما در این مسیر است

# اگر فایل کپی (template) وجود نداشت، آن را از فایل اصلی ایجاد می‌کنیم
if [ ! -f "${HTML_FILE_PATH}.template" ]; then
    cp "$HTML_FILE_PATH" "${HTML_FILE_PATH}.template"
fi

# فایل HTML را از روی تمپلیت بازنویسی می‌کنیم تا Placeholder سر جایش برگردد
cp "${HTML_FILE_PATH}.template" "$HTML_FILE_PATH"

# فرآیند تونل قبلی را در PM2 حذف می‌کنیم
pm2 delete cflare-tunnel > /dev/null 2>&1

# تونل جدید را راه‌اندازی می‌کنیم
# از --no-autoupdate برای جلوگیری از پیام‌های اضافی در لاگ استفاده می‌کنیم
pm2 start "cloudflared tunnel --no-autoupdate --url http://localhost:8000" --name "cflare-tunnel"

# چند ثانیه صبر می‌کنیم تا تونل راه‌اندازی شود
sleep 8

# آدرس URI جدید را از لاگ‌های PM2 استخراج می‌کنیم
URI=$(pm2 logs cflare-tunnel --lines 20 | grep -o 'https://[a-z-]*\.trycloudflare.com' | head -n 1)

if [ -n "$URI" ]; then
    WSS_URI="wss://${URI#https://}"
    echo "--> Updating HTML file with the new URI..."
    # Placeholder را با آدرس جدید در فایل HTML جایگزین می‌کنیم
    sed -i "s|WSS_URI_PLACEHOLDER|${WSS_URI}|g" "$HTML_FILE_PATH"

    echo ""
    echo "✅ New URI Generated Successfully!"
    echo "=================================================="
    echo "Your HTTP address for browser is: ${URI}"
    echo "Your WSS URI for ESP32 is:      ${WSS_URI}"
    echo "=================================================="
else
    echo "❌ Failed to retrieve URI. Please check logs using: pm2 logs cflare-tunnel"
fi

# جلوگیری از پر شدن لاگ‌ها
pm2 flush cflare-tunnel > /dev/null 2>&1