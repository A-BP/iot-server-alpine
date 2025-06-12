#!/bin/bash
echo "--> Attempting to generate a new WSS URI..."

INSTALL_DIR="/opt/iot-server"
HTML_FILE_PATH="${INSTALL_DIR}/public/index.html"
# آدرس فایل لاگ مربوط به تونل (با فرض اینکه اسکریپت با کاربر root اجرا می‌شود)
LOG_FILE="/root/.pm2/logs/cflare-tunnel-out.log"

# ... (کدهای مربوط به بازنویسی فایل HTML با Placeholder) ...
if [ ! -f "${HTML_FILE_PATH}.template" ]; then cp "$HTML_FILE_PATH" "${HTML_FILE_PATH}.template"; fi
cp "${HTML_FILE_PATH}.template" "$HTML_FILE_PATH"

pm2 delete cflare-tunnel > /dev/null 2>&1

echo "--> Starting a new tunnel via PM2..."
pm2 start "cloudflared tunnel --no-autoupdate --url http://localhost:8000" --name "cflare-tunnel"

echo "--> Waiting for tunnel to establish... (up to 30 seconds)"

# --- حلقه هوشمند برای پیدا کردن URI از فایل لاگ ---
URI=""
ATTEMPTS=0
MAX_ATTEMPTS=15

while [ -z "$URI" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    sleep 2
    # بررسی می‌کنیم که آیا فایل لاگ اصلاً ایجاد شده است یا خیر
    if [ -f "$LOG_FILE" ]; then
        # تغییر کلیدی: به جای pm2 logs، مستقیماً فایل لاگ را می‌خوانیم
        URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1)
    fi
    ATTEMPTS=$((ATTEMPTS + 1))
    printf "."
done
# ------------------------------------

echo ""

if [ -n "$URI" ]; then
    WSS_URI="wss://${URI#https://}"
    echo "--> Updating HTML file at ${HTML_FILE_PATH}..."
    sed -i "s|WSS_URI_PLACEHOLDER|${WSS_URI}|g" "$HTML_FILE_PATH"

    echo ""
    echo "✅✅✅ New URI Generated Successfully! ✅✅✅"
    echo "=================================================="
    echo "Your HTTP address for browser is: ${URI}"
    echo "Your WSS URI for ESP32 is:      ${WSS_URI}"
    echo "=================================================="
else
    echo "❌ ERROR: Could not retrieve a tunnel URI after 30 seconds."
    echo "The tunnel started but failed to connect and generate a URL."
    echo "Please check the tunnel logs manually for errors using: pm2 logs cflare-tunnel"
    pm2 delete cflare-tunnel
    exit 1
fi

pm2 flush cflare-tunnel > /dev/null 2>&1