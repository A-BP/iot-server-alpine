#!/bin/bash
echo "--> Attempting to generate a new WSS URI (Robust, Two-Stage Wait)..."

INSTALL_DIR="/opt/iot-server"
HTML_FILE_PATH="${INSTALL_DIR}/public/index.html"
LOG_FILE="/root/.pm2/logs/cflare-tunnel-out.log"

# پاک‌سازی و آماده‌سازی
pm2 delete cflare-tunnel > /dev/null 2>&1
if [ -f "$LOG_FILE" ]; then rm "$LOG_FILE"; fi
if [ -f "${HTML_FILE_PATH}.template" ]; then cp "${HTML_FILE_PATH}.template" "$HTML_FILE_PATH"; fi

echo "--> Starting a new tunnel via PM2..."
pm2 start "/usr/local/bin/cloudflared tunnel --url http://localhost:8000" --name "cflare-tunnel"

# --- مرحله ۱: انتظار هوشمند برای ایجاد فایل لاگ ---
echo "--> Waiting for log file to be created by PM2..."
ATTEMPTS=0
MAX_ATTEMPTS=10 # 10 ثانیه برای ایجاد فایل لاگ
while [ ! -s "$LOG_FILE" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    sleep 1
    ATTEMPTS=$((ATTEMPTS + 1))
    printf "."
done

echo "" # یک خط جدید

# اگر پس از ۱۰ ثانیه فایل لاگ هنوز ساخته نشده، خطا می‌دهیم
if [ ! -s "$LOG_FILE" ]; then
    echo "❌ ERROR: Log file was not created by PM2 after 10 seconds."
    echo "Please check PM2 status with: pm2 list"
    exit 1
fi
# -----------------------------------------------

# --- مرحله ۲: انتظار هوشمند برای پیدا کردن URI در فایل لاگ ---
echo "--> Log file found! Now searching for URI inside it... (up to 40 seconds)"
URI=""
ATTEMPTS=0
MAX_ATTEMPTS=20 # 20 بار تلاش ۲ ثانیه‌ای = ۴۰ ثانیه
while [ -z "$URI" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    sleep 2
    URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1)
    ATTEMPTS=$((ATTEMPTS + 1))
    printf "."
done
# -----------------------------------------------

echo ""

if [ -n "$URI" ]; then
    WSS_URI="wss://${URI#https://}"
    echo "--> Updating HTML file..."
    sed -i "s|WSS_URI_PLACEHOLDER|${WSS_URI}|g" "$HTML_FILE_PATH"

    echo ""
    echo "✅✅✅ SUCCESS! New URI Generated and Applied! ✅✅✅"
    echo "=================================================="
    echo "HTTP address (for browser): ${URI}"
    echo "WSS address (for ESP32):    ${WSS_URI}"
    echo "=================================================="
else
    echo "❌ ERROR: Could not find a URI in the log file after timeout."
    echo "Cloudflared might be having trouble connecting. Check logs with: cat ${LOG_FILE}"
    pm2 delete cflare-tunnel
    exit 1
fi

pm2 flush cflare-tunnel > /dev/null 2>&1