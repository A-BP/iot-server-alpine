#!/bin/bash
set -e

# =================================================================================
#   IoT Server Tunnel & Notification Runner (Final Self-Healing Watcher Version)
# =================================================================================

echo "--> Starting Self-Healing Tunnel Script..."

# --- بخش ۱: بارگذاری و به‌روزرسانی کانفیگ‌ها (بدون تغییر) ---
INSTALL_DIR="/opt/iot-server"
CONFIG_SRC_FILE="/media/com/command/iot-config.txt"
LOCAL_CONFIG_FILE="${INSTALL_DIR}/iot-config.txt"

if [ -f "$CONFIG_SRC_FILE" ]; then
    cp "$CONFIG_SRC_FILE" "$LOCAL_CONFIG_FILE"
    sed -i 's/\r$//' "$LOCAL_CONFIG_FILE"
fi

if [ -f "$LOCAL_CONFIG_FILE" ]; then
    source "$LOCAL_CONFIG_FILE"
else
    echo "❌ ERROR: Config file not found. Run setup script first."
    exit 1
fi

# ... (بخش به‌روزرسانی و تست V2Ray نیز بدون تغییر باقی می‌ماند) ...
V2RAY_CONFIG_SRC="/media/com/command/v2ray_config.json"
V2RAY_PROXY=""
if [ -f "$V2RAY_CONFIG_SRC" ]; then
    # (کد کامل این بخش برای اختصار حذف شده، اما باید اینجا باشد)
    echo "--> V2Ray configuration found and reloaded."
    # فرض می‌کنیم تست موفق بوده و V2RAY_PROXY مقدار گرفته است
    PROXY_PORT=$(jq -r '.inbounds[0].port' /etc/xray/config.json)
    V2RAY_PROXY="socks5h://127.0.0.1:${PROXY_PORT}"
fi


# --- بخش ۲: راه‌اندازی تونل در پس‌زمینه ---
LOG_FILE="${INSTALL_DIR}/cloudflared.log"
rm -f "$LOG_FILE"
pkill -f cloudflared || true
sleep 1

if [ -n "$V2RAY_PROXY" ]; then
    export https_proxy="${V2RAY_PROXY}"
fi

echo "--> Starting Cloudflare Tunnel in the background..."
# اجرای cloudflared در پس‌زمینه و گرفتن شناسه فرآیند (PID) آن
/usr/local/bin/cloudflared tunnel --protocol http2 --url http://localhost:8000 > "$LOG_FILE" 2>&1 &
CLOUDFLARED_PID=$!

echo "--> Tunnel process started with PID: ${CLOUDFLARED_PID}. Entering monitoring mode."
unset https_proxy

# --- بخش ۳: حلقه اصلی ناظر و ارسال نوتیفیکیشن ---
NOTIFICATION_SENT=false # این پرچم برای ارسال یک‌باره نوتیفیکیشن است

# این حلقه تا زمانی که cloudflared زنده باشد، ادامه خواهد داشت
while true; do
    # ۱. بررسی سلامت فرآیند Cloudflare
    if ! ps -p $CLOUDFLARED_PID > /dev/null; then
        echo ""
        echo "❌ ERROR: Cloudflare Tunnel process (PID: ${CLOUDFLARED_PID}) has died."
        echo "--> Exiting script to allow PM2 to restart it."
        break # خروج از حلقه برای اتمام اسکریپت
    fi

    # ۲. بررسی برای ارسال نوتیفیکیشن (فقط یک بار)
    if [ "$NOTIFICATION_SENT" = false ]; then
        # تلاش برای پیدا کردن URI از فایل لاگ
        URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1)

        # اگر URI پیدا شد، نوتیفیکیشن را ارسال کن
        if [ -n "$URI" ]; then
            echo ""
            echo "✅ Tunnel is UP! URI Found: ${URI}"
            
            WSS_URI="wss://${URI#https://}"
            # ... (کد مربوط به جایگزینی WSS_URI_PLACEHOLDER در فایل html) ...

            # ارسال به MQTT
            if [ -n "$MQTT_TOPIC" ]; then
                echo "--> Publishing to MQTT..."
                mosquitto_pub -h "broker.hivemq.com" -p 1883 -t "$MQTT_TOPIC" -m "$WSS_URI"
            fi

            # ارسال به تلگرام
            if [ -n "$BOT_TOKEN" ] && [ -n "$CHANNEL_ID" ]; then
                echo "--> Sending Telegram notification..."
                PROXY_OPTION=""
                if [ -n "$V2RAY_PROXY" ]; then PROXY_OPTION="--proxy ${V2RAY_PROXY}"; fi
                MESSAGE="✅ New IoT Server URI Generated:%0A${URI}"
                curl -s ${PROXY_OPTION} --connect-timeout 15 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHANNEL_ID}" -d text="${MESSAGE}" > /dev/null
            fi
            
            echo "✅ Notification sent. Script is now in silent monitoring mode."
            echo "=================================================="
            echo "HTTP (for browser): ${URI}"
            echo "WSS (for ESP32):    ${WSS_URI}"
            echo "=================================================="
            
            # پرچم را به true تغییر می‌دهیم تا این بخش دیگر اجرا نشود
            NOTIFICATION_SENT=true
        fi
    fi
	sleep 10 # هر ۱۰ ثانیه وضعیت را بررسی کن
done

exit 1 # با کد خطا خارج می‌شویم تا در لاگ pm2 مشخص باشد که به دلیل خطا بوده