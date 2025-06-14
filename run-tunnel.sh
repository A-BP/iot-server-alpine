#!/bin/bash
set -e

# ==============================================================================
#   IoT Server Tunnel & Notification Runner (The Ultimate, Stable Version)
# ==============================================================================

echo "--> Attempting to generate a new WSS URI and publish..."

INSTALL_DIR="/opt/iot-server"
CONFIG_FILE="${INSTALL_DIR}/iot-config.txt"
LOG_FILE="${INSTALL_DIR}/cloudflared.log"

# خواندن تنظیمات از فایل کانفیگ
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ ERROR: Config file not found. Run setup script first."
    exit 1
fi

# پاک‌سازی پروسه‌های قدیمی تونل
pkill -f cloudflared || true
sleep 1
rm -f "$LOG_FILE"

# --- بخش کلیدی ۱: تنظیم پروکسی برای پایداری Cloudflare ---
# این بخش تضمین می‌کند که خود تونل کلودفلر هم از طریق V2Ray عبور کند
V2RAY_CONFIG_FILE="/etc/xray/config.json"
if [ -f "$V2RAY_CONFIG_FILE" ]; then
    PROXY_PORT=$(jq -r '.inbounds[0].port' "$V2RAY_CONFIG_FILE")
    V2RAY_PROXY="socks5h://127.0.0.1:${PROXY_PORT}"
    echo "--> V2Ray proxy detected. Forcing Cloudflare Tunnel to use it for stability..."
    # متغیر محیطی را برای پروسه بعدی تنظیم می‌کنیم
    export https_proxy="${V2RAY_PROXY}"
fi
# ----------------------------------------------------

# --- اجرای Cloudflare Tunnel ---
# این پروسه حالا از پروکسی تنظیم شده در بالا استفاده خواهد کرد
nohup /usr/local/bin/cloudflared tunnel --protocol http2 --url http://localhost:8000 > "$LOG_FILE" 2>&1 &

echo "--> Waiting for tunnel to establish... (up to 40 seconds)"

# --- حلقه هوشمند برای پیدا کردن URI از فایل لاگ ---
URI=""
ATTEMPTS=0
MAX_ATTEMPTS=20
while [ -z "$URI" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    sleep 2
    if [ -f "$LOG_FILE" ]; then
        URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1)
    fi
    ATTEMPTS=$((ATTEMPTS + 1)); printf ".";
done
echo ""

if [ -n "$URI" ]; then
    # پس از پیدا کردن URI، متغیر پروکسی را پاک می‌کنیم تا روی دستورات دیگر تاثیر نگذارد (اختیاری)
    unset https_proxy

    WSS_URI="wss://${URI#https://}"
    HTML_FILE_PATH="${INSTALL_DIR}/public/index.html"
    if [ -f "${HTML_FILE_PATH}.template" ]; then cp "${HTML_FILE_PATH}.template" "$HTML_FILE_PATH"; fi
    sed -i "s|WSS_URI_PLACEHOLDER|${WSS_URI}|g" "$HTML_FILE_PATH"

    # ارسال به MQTT
    if [ -n "$MQTT_TOPIC" ]; then
        echo "--> Publishing to MQTT Topic: ${MQTT_TOPIC}"
        mosquitto_pub -h "broker.hivemq.com" -p 1883 -t "$MQTT_TOPIC" -m "$WSS_URI"
    fi

    # --- بخش کلیدی ۲: ارسال و تست هوشمند تلگرام ---
    if [ -n "$BOT_TOKEN" ] && [ -n "$CHANNEL_ID" ]; then
        echo "--> Sending and verifying Telegram notification..."
        PROXY_OPTION=""
        if [ -n "$V2RAY_PROXY" ]; then PROXY_OPTION="--proxy ${V2RAY_PROXY}"; fi
        MESSAGE="✅ New IoT Server URI Generated:%0A${URI}"
        
        TELEGRAM_RESPONSE=$(curl -s ${PROXY_OPTION} --connect-timeout 15 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHANNEL_ID}" -d text="${MESSAGE}")
        
        if echo "${TELEGRAM_RESPONSE}" | jq -e '.ok' > /dev/null; then
            echo "✅ Telegram notification sent successfully!"
        else
            echo "❌ WARNING: Telegram notification failed."
            ERROR_DESC=$(echo "${TELEGRAM_RESPONSE}" | jq -r '.description')
            echo "--> Telegram API Error: ${ERROR_DESC}"
        fi
    fi
    # ---------------------------------------------
    
    echo ""
    echo "✅✅✅ SUCCESS! URI is Ready and Stable! ✅✅✅"
    echo "=================================================="
    echo "HTTP (for browser): ${URI}"
    echo "WSS (for ESP32):    ${WSS_URI}"
    echo "=================================================="
else
    echo "❌ ERROR: Could not retrieve a tunnel URI after 40 seconds."
    exit 1
fi