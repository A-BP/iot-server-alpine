#!/bin/bash
# 'set -e' باعث می‌شود اسکریپت با اولین خطا متوقف شود
set -e

# ==============================================================================
#   IoT Server Unified Setup Script (Final Version with All Features & Fixes)
# ==============================================================================

# --- تابع اصلی برای تولید URI و ارسال نوتیفیکیشن ---
generate_and_publish_uri() {
    echo "--> Attempting to generate a new WSS URI and publish..."
    INSTALL_DIR="/opt/iot-server"
    LOG_FILE="${INSTALL_DIR}/cloudflared.log"
    # هر پروسه cloudflared قبلی را متوقف می‌کند
    pkill -f cloudflared || true
    sleep 1
    rm -f "$LOG_FILE"
    
    # راه‌اندازی تونل در پس‌زمینه با روش استاندارد nohup
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
        ATTEMPTS=$((ATTEMPTS + 1)); printf ".";
    done
    echo ""

    if [ -n "$URI" ]; then
        WSS_URI="wss://${URI#https://}"
        HTML_FILE_PATH="${INSTALL_DIR}/public/index.html"
        # آپدیت فایل HTML با Placeholder
        if [ -f "${HTML_FILE_PATH}.template" ]; then cp "${HTML_FILE_PATH}.template" "$HTML_FILE_PATH"; fi
        sed -i "s|WSS_URI_PLACEHOLDER|${WSS_URI}|g" "$HTML_FILE_PATH"

        # ارسال به MQTT (اگر در کانفیگ تعریف شده باشد)
        if [ -n "$MQTT_TOPIC" ]; then
            echo "--> Publishing to MQTT Topic: ${MQTT_TOPIC}"
            mosquitto_pub -h "broker.hivemq.com" -p 1883 -t "$MQTT_TOPIC" -m "$WSS_URI"
        fi

        # ارسال و تست نوتیفیکیشن تلگرام
        if [ -n "$BOT_TOKEN" ] && [ -n "$CHANNEL_ID" ]; then
            PROXY_OPTION=""
            if [ -n "$V2RAY_PROXY" ]; then PROXY_OPTION="--proxy ${V2RAY_PROXY}"; fi
            echo "--> Sending and verifying Telegram notification..."
            MESSAGE="✅ New IoT Server URI Generated:%0A${URI}"
            
            # خروجی curl را در یک متغیر ذخیره می‌کنیم تا پاسخ تلگرام را بررسی کنیم
            TELEGRAM_RESPONSE=$(curl -s ${PROXY_OPTION} --connect-timeout 15 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHANNEL_ID}" -d text="${MESSAGE}")
            
            # با jq پاسخ را بررسی می‌کنیم
            if echo "${TELEGRAM_RESPONSE}" | jq -e '.ok' > /dev/null; then
                echo "✅ Telegram notification sent successfully!"
            else
                echo "❌ WARNING: Telegram notification failed."
                ERROR_DESC=$(echo "${TELEGRAM_RESPONSE}" | jq -r '.description')
                echo "--> Telegram API Error: ${ERROR_DESC}"
            fi
        fi
        
        echo ""
        echo "✅✅✅ SUCCESS! URI is Ready! ✅✅✅"
        echo "=================================================="
        echo "HTTP (for browser): ${URI}"
        echo "WSS (for ESP32):    ${WSS_URI}"
        echo "=================================================="
    else
        echo "❌ ERROR: Could not retrieve a tunnel URI after 40 seconds."
        echo "Please check the log file for errors: cat ${LOG_FILE}"
        exit 1
    fi
}
# --- پایان تعریف تابع ---


# ==================================
# ===== شروع اسکریپت اصلی نصب =====
# ==================================
echo "### Starting IoT Server Setup ###"

# نصب پیش‌نیاز اولیه برای اصلاح فایل‌ها
apk update
apk add coreutils

# خواندن و اصلاح فایل iot-config.txt
CONFIG_SRC_FILE="/media/com/command/iot-config.txt"
if [ ! -f "$CONFIG_SRC_FILE" ]; then echo "❌ ERROR: Config file not found at ${CONFIG_SRC_FILE}!"; exit 1; fi
echo "--> Converting and reading configuration from ${CONFIG_SRC_FILE}..."
# ابتدا با sed کاراکترهای ویندوزی را حذف می‌کنیم
sed -i 's/\r$//' "$CONFIG_SRC_FILE"
source "$CONFIG_SRC_FILE"
# فعال‌سازی مخزن Community و به‌روزرسانی
echo "--> Enabling 'community' repository and updating..."
sed -i -e 's/^#\(.*\/community\)$/\1/' /etc/apk/repositories
apk update

# نصب تمام پیش‌نیازها
echo "--> Installing all dependencies..."
apk add bash nodejs npm git curl mosquitto-clients tzdata openntpd unzip jq

# تنظیم منطقه زمانی و همگام‌سازی ساعت
echo "--> Setting timezone to Asia/Tehran and syncing time..."
ln -sf /usr/share/zoneinfo/Asia/Tehran /etc/localtime
echo "Asia/Tehran" > /etc/timezone
rc-service openntpd start
rc-update add openntpd default

# نصب PM2 و Cloudflared
echo "--> Installing core services..."
npm install -g pm2
curl -L -o /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /usr/local/bin/cloudflared

# بخش V2Ray
V2RAY_CONFIG_SRC="/media/com/command/v2ray_config.json"
if [ -f "$V2RAY_CONFIG_SRC" ]; then
    echo "--> V2Ray config file found. Installing and configuring Xray..."
    # اصلاح خودکار فرمت فایل کانفیگ V2Ray
    sed -i 's/\r$//' "$V2RAY_CONFIG_SRC"
    
    curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
    unzip -o xray.zip -d /usr/local/bin/ && rm xray.zip && chmod +x /usr/local/bin/xray
    
    XRAY_CONFIG_FILE="/etc/xray/config.json"
    mkdir -p /etc/xray
    cp "$V2RAY_CONFIG_SRC" "$XRAY_CONFIG_FILE"

    pm2 delete xray-client > /dev/null 2>&1 || true
    # اجرای Xray با دستور صحیح برای PM2
    pm2 start /usr/local/bin/xray --name "xray-client" -- -c "$XRAY_CONFIG_FILE"
    
    echo "--> Testing V2Ray proxy connection..."
    sleep 5
    PROXY_PORT=$(jq -r '.inbounds[0].port' "$XRAY_CONFIG_FILE")
    export V2RAY_PROXY="socks5h://127.0.0.1:${PROXY_PORT}"
    if curl -s --proxy "$V2RAY_PROXY" --connect-timeout 15 "https://www.google.com" > /dev/null; then
        echo "✅ V2Ray proxy test successful!"
    else
        echo "❌ WARNING: V2Ray proxy test failed. Telegram notifications may not work."
    fi
else
    echo "--> No V2Ray config file found, skipping V2Ray setup."
fi

# دانلود کد از گیت‌هاب و راه‌اندازی سرور
GITHUB_REPO_URL="https://github.com/A-BP/iot-server-alpine.git"
INSTALL_DIR="/opt/iot-server"
echo "--> Cloning project and installing dependencies..."
rm -rf "${INSTALL_DIR}"
git clone "${GITHUB_REPO_URL}" "${INSTALL_DIR}"
cp "$CONFIG_SRC_FILE" "${INSTALL_DIR}/iot-config.txt"
cd "${INSTALL_DIR}" && npm install
pm2 delete iot-app > /dev/null 2>&1 || true
pm2 start server.js --name "iot-app" --cwd "${INSTALL_DIR}"
pm2 save
pm2 startup openrc -u root --hp /root

# فراخوانی تابع تولید URI
generate_and_publish_uri

# نمایش ساعت نهایی
echo ""
echo "--> Final System Time:"
date
echo ""
echo "### Initial Setup Is Complete! ###"