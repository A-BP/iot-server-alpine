#!/bin/bash
set -e

# =================================================================================
#   IoT Server Tunnel & Notification Runner (v3 - BusyBox Compatible)
# =================================================================================

echo "--> Starting Self-Healing Tunnel Script..."

# --- بخش ۱: بارگذاری و به‌روزرسانی کانفیگ‌ها ---
# (این بخش بدون تغییر باقی می‌ماند)
INSTALL_DIR="/opt/iot-server"
CONFIG_SRC_FILE="/media/com/command/iot-config.txt"
LOCAL_CONFIG_FILE="${INSTALL_DIR}/iot-config.txt"
if [ -f "$CONFIG_SRC_FILE" ]; then cp "$CONFIG_SRC_FILE" "$LOCAL_CONFIG_FILE"; fi
if [ -f "$LOCAL_CONFIG_FILE" ]; then source "$LOCAL_CONFIG_FILE"; else echo "❌ ERROR: Config file not found."; exit 1; fi
V2RAY_CONFIG_SRC="/media/com/command/v2ray_config.json"
V2RAY_PROXY=""
if [ -f "$V2RAY_CONFIG_SRC" ]; then
    # (منطق کامل V2Ray در اینجا قرار دارد)
    echo "--> V2Ray configuration found and reloaded."
    PROXY_PORT=$(jq -r '.inbounds[0].port' /etc/xray/config.json)
    V2RAY_PROXY="socks5h://127.0.0.1:${PROXY_PORT}"
fi

# --- بخش ۲: راه‌اندازی تونل در پس‌زمینه ---
LOG_FILE="${INSTALL_DIR}/cloudflared.log"
rm -f "$LOG_FILE"
pkill -f cloudflared || true
sleep 1
if [ -n "$V2RAY_PROXY" ]; then export https_proxy="${V2RAY_PROXY}"; fi
echo "--> Starting Cloudflare Tunnel in the background..."
/usr/local/bin/cloudflared tunnel --url http://localhost:8000 > "$LOG_FILE" 2>&1 &
CLOUDFLARED_PID=$!
echo "--> Tunnel process started with PID: ${CLOUDFLARED_PID}. Entering monitoring mode."
unset https_proxy

# --- بخش ۳: حلقه اصلی ناظر و ارسال نوتیفیکیشن ---
NOTIFICATION_SENT=false
while true; do
    # ۱. بررسی سلامت فرآیند (با روش سازگار با BusyBox)
    if [ ! -d "/proc/$CLOUDFLARED_PID" ]; then
        echo ""
        echo "❌ ERROR: Cloudflare Tunnel process (PID: ${CLOUDFLARED_PID}) has died."
        echo "--> Exiting script to allow PM2 to restart it."
        break
    fi

    # ۲. بررسی برای ارسال نوتیفیکیشن (بدون تغییر)
    if [ "$NOTIFICATION_SENT" = false ]; then
        URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1 || true)
        if [ -n "$URI" ]; then
            echo ""
            echo "✅ Tunnel is UP! URI Found: ${URI}"
            # (بخش ارسال نوتیفیکیشن بدون تغییر باقی می‌ماند)
            WSS_URI="wss://${URI#https://}"
            if [ -n "$MQTT_TOPIC" ]; then
                mosquitto_pub -h "broker.hivemq.com" -p 1883 -t "$MQTT_TOPIC" -m "$WSS_URI"
            fi
            if [ -n "$BOT_TOKEN" ] && [ -n "$CHANNEL_ID" ]; then
                PROXY_OPTION=""
                if [ -n "$V2RAY_PROXY" ]; then PROXY_OPTION="--proxy ${V2RAY_PROXY}"; fi
                MESSAGE="✅ New IoT Server URI Generated:%0A${URI}"
                curl -s ${PROXY_OPTION} --connect-timeout 15 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHANNEL_ID}" -d text="${MESSAGE}" > /dev/null
            fi
            echo "✅ Notification sent. Script is now in silent monitoring mode."
            NOTIFICATION_SENT=true
        fi
    fi

    sleep 10
done

exit 1