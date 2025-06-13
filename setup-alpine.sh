#!/bin/bash
set -e

# ==============================================================================
#   IoT Server Unified Setup Script (v11 - Self-Testing Final Version)
# ==============================================================================

# --- تابع اصلی برای تولید URI و ارسال نوتیفیکیشن ---
generate_and_publish_uri() {
    echo "--> Attempting to generate a new WSS URI and publish..."
    INSTALL_DIR="/opt/iot-server"
    LOG_FILE="${INSTALL_DIR}/cloudflared.log"
    pkill -f cloudflared || true
    sleep 1
    rm -f "$LOG_FILE"
    nohup /usr/local/bin/cloudflared tunnel --url http://localhost:8000 > "$LOG_FILE" 2>&1 &
    echo "--> Waiting for tunnel to establish... (up to 40 seconds)"
    URI=""
    ATTEMPTS=0
    MAX_ATTEMPTS=20
    while [ -z "$URI" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        sleep 2
        if [ -f "$LOG_FILE" ]; then URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1); fi
        ATTEMPTS=$((ATTEMPTS + 1)); printf ".";
    done
    echo ""

    if [ -n "$URI" ]; then
        WSS_URI="wss://${URI#https://}"
        HTML_FILE_PATH="${INSTALL_DIR}/public/index.html"
        if [ -f "${HTML_FILE_PATH}.template" ]; then cp "${HTML_FILE_PATH}.template" "$HTML_FILE_PATH"; fi
        sed -i "s|WSS_URI_PLACEHOLDER|${WSS_URI}|g" "$HTML_FILE_PATH"

        if [ -n "$MQTT_TOPIC" ]; then
            echo "--> Publishing to MQTT Topic: ${MQTT_TOPIC}"
            mosquitto_pub -h "broker.hivemq.com" -p 1883 -t "$MQTT_TOPIC" -m "$WSS_URI"
        fi

        if [ -n "$BOT_TOKEN" ] && [ -n "$CHANNEL_ID" ]; then
            PROXY_OPTION=""
            if [ -n "$V2RAY_PROXY" ]; then PROXY_OPTION="--proxy ${V2RAY_PROXY}"; fi
            echo "--> Sending Telegram notification..."
            MESSAGE="✅ New IoT Server URI Generated:%0A${URI}"
            # تایم‌اوت ۱۰ ثانیه‌ای اضافه شده تا اسکریپت گیر نکند
            curl -s ${PROXY_OPTION} --connect-timeout 10 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHANNEL_ID}" -d text="${MESSAGE}" > /dev/null || echo "--> WARNING: Telegram notification failed, but continuing."
        fi
        
        # --- نمایش URI به عنوان آخرین خروجی اصلی ---
        echo ""
        echo "✅✅✅ SUCCESS! URI is Ready! ✅✅✅"
        echo "=================================================="
        echo "HTTP (for browser): ${URI}"
        echo "WSS (for ESP32):    ${WSS_URI}"
        echo "=================================================="
    else
        echo "❌ ERROR: Could not retrieve a tunnel URI after 40 seconds."
        exit 1
    fi
}
# --- پایان تعریف تابع ---


# ===== شروع اسکریپت اصلی نصب =====
echo "### Starting IoT Server Setup ###"

# خواندن تنظیمات از فایل روی فلش
CONFIG_SRC_FILE="/media/com/command/iot-config.txt"
if [ ! -f "$CONFIG_SRC_FILE" ]; then echo "❌ ERROR: Config file not found at ${CONFIG_SRC_FILE}!"; exit 1; fi
echo "--> Reading configuration from ${CONFIG_SRC_FILE}..."
source "$CONFIG_SRC_FILE"

# نصب پیش‌نیازها
echo "--> Installing dependencies..."
sed -i -e 's/^#\(.*\/community\)$/\1/' /etc/apk/repositories
apk update
# ntp-client برای همگام‌سازی یک‌باره و سریع ساعت اضافه شد
apk add bash nodejs npm git curl mosquitto-clients unzip ntp-client

# تنظیم ساعت با روش مستقیم
echo "--> Setting timezone and syncing clock..."
ln -sf /usr/share/zoneinfo/Asia/Tehran /etc/localtime
# همگام‌سازی یک‌باره ساعت با سرورهای NTP
ntp-client -s -h pool.ntp.org

# نصب PM2, Cloudflared, Xray
echo "--> Installing core services..."
npm install -g pm2
curl -L -o /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /usr/local/bin/cloudflared
curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip -o xray.zip -d /usr/local/bin/ && rm xray.zip && chmod +x /usr/local/bin/xray
# پیکربندی و اجرای V2Ray/Xray (اگر لینک آن ارائه شده باشد)
if [ -n "$V2RAY_LINK" ]; then
    echo "--> Configuring Xray (V2Ray client)..."
    VMESS_JSON=$(echo "${V2RAY_LINK#vmess://}" | base64 -d)
    XRAY_CONFIG_FILE="/etc/xray/config.json"
    mkdir -p /etc/xray
    tee "$XRAY_CONFIG_FILE" > /dev/null <<EOF
{ "inbounds": [{"port": 1080, "listen": "127.0.0.1", "protocol": "socks", "settings": {"auth": "noauth", "udp": true}}], "outbounds": [${VMESS_JSON}] }
EOF
    pm2 delete xray-client > /dev/null 2>&1 || true
    pm2 start "/usr/local/bin/xray -c /etc/xray/config.json" --name "xray-client"
    
    # --- تست جدید برای V2Ray ---
    echo "--> Testing V2Ray proxy connection..."
    sleep 5 # زمان برای راه‌اندازی Xray
    # ما از گوگل برای تست استفاده می‌کنیم چون فیلتر نیست و به پروکسی نیاز ندارد
    # اما با عبور از پروکسی، باید آی‌پی سرور V2Ray را برگرداند
    if curl -s --proxy socks5h://127.0.0.1:1080 --connect-timeout 10 "https://www.google.com" > /dev/null; then
        echo "✅ V2Ray proxy test successful!"
    else
        echo "❌ WARNING: V2Ray proxy test failed. Telegram notifications may not work."
    fi
    # -------------------------
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

# فراخوانی تابع تولید URI به عنوان آخرین مرحله اصلی
generate_and_publish_uri

# نمایش ساعت نهایی به عنوان آخرین پیام
echo ""
echo "--> Final System Time:"
date
echo ""
echo "### Setup Is Complete! ###"