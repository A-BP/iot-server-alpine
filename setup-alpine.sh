#!/bin/bash
# 'set -e' باعث می‌شود اسکریپت با اولین خطا متوقف شود
set -e

# ==============================================================================
#   IoT Server Unified Setup Script (Final Version for USB Config)
# ==============================================================================

# --- تابع اصلی برای تولید URI و ارسال نوتیفیکیشن ---
# این تابع تمام منطق مربوط به تونل و اطلاع‌رسانی را در خود دارد
generate_and_publish_uri() {
    echo "--> Attempting to generate a new WSS URI and publish..."

    INSTALL_DIR="/opt/iot-server"
    LOG_FILE="${INSTALL_DIR}/cloudflared.log"

    # پاک‌سازی تونل قبلی
    pkill -f cloudflared || true
    sleep 1
    rm -f "$LOG_FILE"
    
    # راه‌اندازی تونل در پس‌زمینه با روش nohup
    nohup /usr/local/bin/cloudflared tunnel --url http://localhost:8000 > "$LOG_FILE" 2>&1 &

    echo "--> Waiting for tunnel to establish... (up to 40 seconds)"

    URI=""
    ATTEMPTS=0
    MAX_ATTEMPTS=20
    while [ -z "$URI" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        sleep 2
        if [ -f "$LOG_FILE" ]; then
            URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1)
        fi
        ATTEMPTS=$((ATTEMPTS + 1))
        printf "."
    done
    echo ""

    if [ -n "$URI" ]; then
        WSS_URI="wss://${URI#https://}"
        
        # آپدیت فایل HTML
        HTML_FILE_PATH="${INSTALL_DIR}/public/index.html"
        if [ -f "${HTML_FILE_PATH}.template" ]; then cp "${HTML_FILE_PATH}.template" "$HTML_FILE_PATH"; fi
        sed -i "s|WSS_URI_PLACEHOLDER|${WSS_URI}|g" "$HTML_FILE_PATH"

        # ارسال به MQTT (اگر متغیر آن در کانفیگ وجود داشته باشد)
        if [ -n "$MQTT_TOPIC" ]; then
            echo "--> Publishing to MQTT Topic: ${MQTT_TOPIC}"
            mosquitto_pub -h "broker.hivemq.com" -p 1883 -t "$MQTT_TOPIC" -m "$WSS_URI"
        fi

        # ارسال به تلگرام (اگر متغیرهای آن در کانفیگ وجود داشته باشد)
        if [ -n "$BOT_TOKEN" ] && [ -n "$CHANNEL_ID" ]; then
            PROXY_OPTION=""
            if [ -n "$V2RAY_PROXY" ]; then
                PROXY_OPTION="--proxy ${V2RAY_PROXY}"
                echo "--> Sending Telegram notification via V2Ray proxy..."
            else
                echo "--> Sending Telegram notification..."
            fi
            MESSAGE="✅ New IoT Server URI Generated:%0A${URI}"
            curl -s ${PROXY_OPTION} -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHANNEL_ID}" -d text="${MESSAGE}" > /dev/null
        fi

        echo ""
        echo "✅✅✅ SUCCESS! URI is Ready! ✅✅✅"
        echo "=================================================="
        echo "HTTP (for browser): ${URI}"
        echo "WSS (for ESP32):    ${WSS_URI}"
        echo "=================================================="
    else
        echo "❌ ERROR: Could not retrieve a tunnel URI after 40 seconds."
        echo "Please check logs for errors: cat ${LOG_FILE}"
        exit 1
    fi
}
# --- پایان تعریف تابع ---


# ==================================
# ===== شروع اسکریپت اصلی نصب =====
# ==================================

# خواندن تنظیمات از فایل روی فلش
CONFIG_SRC_FILE="/media/com/command/iot-config.txt"
if [ ! -f "$CONFIG_SRC_FILE" ]; then
    echo "❌ CRITICAL ERROR: Config file not found at ${CONFIG_SRC_FILE}!"
    exit 1
fi
echo "--> Reading configuration from ${CONFIG_SRC_FILE}..."
# دستور source متغیرها را برای کل این اسکریپت قابل دسترس می‌کند
source "$CONFIG_SRC_FILE"

# نصب تمام پیش‌نیازها
echo "--> Installing dependencies..."
sed -i -e 's/^#\(.*\/community\)$/\1/' /etc/apk/repositories
apk update
apk add bash nodejs npm git curl mosquitto-clients tzdata openntpd

# تنظیم منطقه زمانی و همگام‌سازی ساعت
echo "--> Setting timezone to Asia/Tehran and syncing time..."
cp /usr/share/zoneinfo/Asia/Tehran /etc/localtime
echo "Asia/Tehran" > /etc/timezone
rc-service openntpd start
rc-update add openntpd default
# نصب PM2 و Cloudflared
echo "--> Installing core services..."
npm install -g pm2
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
mv cloudflared /usr/local/bin/

# دانلود کد از گیت‌هاب و کپی کردن کانفیگ
GITHUB_REPO_URL="https://github.com/A-BP/iot-server-alpine.git"
INSTALL_DIR="/opt/iot-server"
echo "--> Cloning project from GitHub..."
rm -rf "${INSTALL_DIR}"
git clone "${GITHUB_REPO_URL}" "${INSTALL_DIR}"
cp "$CONFIG_SRC_FILE" "${INSTALL_DIR}/iot-config.txt"
cd "${INSTALL_DIR}" && npm install

# راه‌اندازی سرور Node.js با PM2
echo "--> Starting Node.js server..."
pm2 delete iot-app > /dev/null 2>&1 || true
pm2 start server.js --name "iot-app" --cwd "${INSTALL_DIR}"
pm2 save
pm2 startup openrc -u root --hp /root

# --- فراخوانی تابع اصلی به عنوان آخرین مرحله ---
generate_and_publish_uri

# --- نمایش ساعت تنظیم شده در انتها ---
echo ""
echo "--------------------------------------------------"
echo "--> Final system time has been set to:"
date
echo "--------------------------------------------------"

echo "### Initial Setup Is Complete! ###"