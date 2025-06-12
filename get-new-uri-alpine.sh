#!/bin/bash
echo "--> Attempting to generate a new WSS URI and publish to MQTT..."

INSTALL_DIR="/opt/iot-server"
CONFIG_FILE="${INSTALL_DIR}/.env"

# --- بخش جدید: خواندن تنظیمات از فایل کانفیگ ---
if [ -f "$CONFIG_FILE" ]; then
    # دستور source فایل را اجرا کرده و متغیرهای آن را در محیط فعلی تعریف می‌کند
    source "$CONFIG_FILE"
else
    echo "❌ ERROR: Configuration file not found at ${CONFIG_FILE}"
    exit 1
fi
# ----------------------------------------------------

# مقادیر پیش‌فرض در صورتی که در فایل کانفیگ تعریف نشده باشند
MQTT_BROKER=${MQTT_BROKER:-"broker.hivemq.com"}
MQTT_PORT=${MQTT_PORT:-"1883"}

# ... (بقیه کد دقیقاً مانند قبل است و از متغیرهای خوانده شده استفاده می‌کند) ...
LOG_FILE="${INSTALL_DIR}/cloudflared.log"
pkill -f cloudflared || true
sleep 1
rm -f "$LOG_FILE"
nohup /usr/local/bin/cloudflared tunnel --url http://localhost:8000 > "$LOG_FILE" 2>&1 &

echo "--> Waiting for tunnel to establish..."
# ... (حلقه while برای پیدا کردن URI) ...
URI=""
ATTEMPTS=0
MAX_ATTEMPTS=30
while [ -z "$URI" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do sleep 2; if [ -f "$LOG_FILE" ]; then URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1); fi; ATTEMPTS=$((ATTEMPTS + 1)); printf "."; done
echo ""

if [ -n "$URI" ]; then
    WSS_URI="wss://${URI#https://}"
    
    # ... (بخش آپدیت HTML مانند قبل) ...
    
    # --- بخش جدید: ارسال پیام با استفاده از متغیرهای شخصی‌سازی شده ---
    echo "--> Publishing new WSS URI to MQTT topic: ${MQTT_TOPIC}"
    mosquitto_pub -h "$MQTT_BROKER" -p "$MQTT_PORT" -t "$MQTT_TOPIC" -m "$WSS_URI"
    
    # اگر توکن تلگرام وارد شده باشد، نوتیفیکیشن ارسال می‌شود
    if [ -n "$BOT_TOKEN" ] && [ -n "$CHANNEL_ID" ]; then
        echo "--> Sending notification to Telegram..."
        MESSAGE="✅ New URI for your IoT server is ready:%0A${URI}"
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHANNEL_ID}" -d text="${MESSAGE}" > /dev/null
    fi
    # --------------------------------------------------------------------

    echo ""
    echo "✅✅✅ SUCCESS! New URI Generated and Published! ✅✅✅"
    echo "WSS address (for ESP32 via MQTT): ${WSS_URI}"
else
    echo "❌ ERROR: Could not retrieve a tunnel URI."
    exit 1
fi