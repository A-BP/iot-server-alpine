#!/bin/bash
echo "--> Attempting to generate a new WSS URI (using nohup method)..."

INSTALL_DIR="/opt/iot-server"
HTML_FILE_PATH="${INSTALL_DIR}/public/index.html"
LOG_FILE="${INSTALL_DIR}/cloudflared.log"

# --- پاک‌سازی و آماده‌سازی ---
echo "--> Cleaning up old tunnel processes and logs..."
# هر پروسه cloudflared قبلی را متوقف می‌کند
pkill -f cloudflared || true
sleep 1
rm -f "$LOG_FILE"
if [ -f "${HTML_FILE_PATH}.template" ]; then cp "${HTML_FILE_PATH}.template" "$HTML_FILE_PATH"; fi

# --- اجرای cloudflared با روش استاندارد لینوکس ---
echo "--> Starting a new tunnel in the background..."
nohup /usr/local/bin/cloudflared tunnel --url http://localhost:8000 > "$LOG_FILE" 2>&1 &

echo "--> Waiting for tunnel to establish... (up to 30 seconds)"

# --- حلقه هوشمند برای پیدا کردن URI از فایل لاگ جدید ---
URI=""
ATTEMPTS=0
MAX_ATTEMPTS=15
while [ -z "$URI" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    sleep 2
    if [ -f "$LOG_FILE" ]; then
        URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1)
    fi
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
    echo "✅✅✅ SUCCESS! New URI Generated! ✅✅✅"
    echo "=================================================="
    echo "HTTP address (for browser): ${URI}"
    echo "WSS address (for ESP32):    ${WSS_URI}"
    echo "=================================================="
else
    echo "❌ ERROR: Could not retrieve a tunnel URI after 30 seconds."
    echo "Please check the log file for errors: cat ${LOG_FILE}"
    exit 1
fi