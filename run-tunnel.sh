#!/bin/bash
set -e

# =================================================================================
#   IoT Server Tunnel & Notification Runner (v4 - The Ultimate Combined Version)
# =================================================================================

echo "--> Starting Self-Healing Tunnel Script..."

# --- بخش ۱: بارگذاری و به‌روزرسانی کانفیگ‌ها ---
INSTALL_DIR="/opt/iot-server"
CONFIG_SRC_FILE="/media/com/command/iot-config.txt"
LOCAL_CONFIG_FILE="${INSTALL_DIR}/iot-config.txt"
if [ -f "$CONFIG_SRC_FILE" ]; then cp "$CONFIG_SRC_FILE" "$LOCAL_CONFIG_FILE"; sed -i 's/\r$//' "$LOCAL_CONFIG_FILE"; fi
if [ -f "$LOCAL_CONFIG_FILE" ]; then source "$LOCAL_CONFIG_FILE"; else echo "❌ ERROR: Config file not found."; exit 1; fi

# --- بخش ۲: به‌روزرسانی و تست کامل V2Ray ---
V2RAY_CONFIG_SRC="/media/com/command/v2ray_config.json"
V2RAY_PROXY=""
if [ -f "$V2RAY_CONFIG_SRC" ]; then
    echo "--> V2Ray config file found. Re-configuring and testing..."
    sed -i 's/\r$//' "$V2RAY_CONFIG_SRC"
    mkdir -p /etc/xray && cp "$V2RAY_CONFIG_SRC" /etc/xray/config.json
    
    if ! pm2 restart xray-client > /dev/null 2>&1; then
        pm2 start /usr/local/bin/xray --name "xray-client" -- -c /etc/xray/config.json
    fi
    sleep 5

    PROXY_PORT=$(jq -r '.inbounds[0].port' /etc/xray/config.json)
    TEST_PROXY="socks5h://127.0.0.1:${PROXY_PORT}"

    echo "--> Testing V2Ray proxy connection..."
    if curl -s --proxy "$TEST_PROXY" --connect-timeout 15 "https://www.google.com" > /dev/null; then
        echo "✅ V2Ray proxy test successful!"
        V2RAY_PROXY="$TEST_PROXY" # فقط در صورت موفقیت، متغیر اصلی را تنظیم کن
    else
        echo "❌ WARNING: V2Ray proxy test FAILED. Telegram notifications may not work."
    fi
fi

# --- بخش ۳: راه‌اندازی تونل Cloudflare ---
LOG_FILE="${INSTALL_DIR}/cloudflared.log"
rm -f "$LOG_FILE"
pkill -f cloudflared || true
sleep 1
if [ -n "$V2RAY_PROXY" ]; then export https_proxy="${V2RAY_PROXY}"; fi
echo "--> Starting Cloudflare Tunnel in the background..."
/usr/local/bin/cloudflared tunnel --protocol http2 --url http://localhost:8000 > "$LOG_FILE" 2>&1 &
CLOUDFLARED_PID=$!
echo "--> Tunnel process started with PID: ${CLOUDFLARED_PID}. Entering monitoring mode."
unset https_proxy

# --- بخش ۴: حلقه اصلی ناظر و ارسال کامل نوتیفیکیشن ---
NOTIFICATION_SENT=false
while true; do
    if [ ! -d "/proc/$CLOUDFLARED_PID" ]; then
        echo ""
        echo "❌ ERROR: Cloudflare Tunnel process (PID: ${CLOUDFLARED_PID}) has died."
        echo "--> Exiting script to allow PM2 to restart it."
        break
    fi

    if [ "$NOTIFICATION_SENT" = false ]; then
        URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1 || true)
        
        if [ -n "$URI" ]; then
            WSS_URI="wss://${URI#https://}"
            
            # ارسال به MQTT
            if [ -n "$MQTT_TOPIC" ]; then
                echo "--> Publishing to MQTT Topic: ${MQTT_TOPIC}"
                mosquitto_pub -h "broker.hivemq.com" -p 1883 -t "$MQTT_TOPIC" -m "$WSS_URI"
            fi

            # ارسال و تست هوشمند تلگرام
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
			echo ""
            echo "✅✅✅ SUCCESS! URI is Ready and Stable! ✅✅✅"
            echo "=================================================="
            echo "HTTP (for browser): ${URI}"
            echo "WSS (for ESP32):    ${WSS_URI}"
            echo "=================================================="
            echo "Script is now in silent monitoring mode. Press Ctrl+C to exit if running manually."
            
            NOTIFICATION_SENT=true
        fi
    fi

    sleep 10
done

exit 1