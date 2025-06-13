#!/bin/bash
set -e

# ==============================================================================
#   IoT Server Initial Setup Script (Final Feature-Complete Version)
# ==============================================================================

echo "### Starting IoT Server One-Time Setup ###"

# خواندن و اصلاح فایل iot-config.txt
CONFIG_SRC_FILE="/media/com/command/iot-config.txt"
if [ ! -f "$CONFIG_SRC_FILE" ]; then echo "❌ ERROR: Config file not found at ${CONFIG_SRC_FILE}!"; exit 1; fi
sed -i 's/\r$//' "$CONFIG_SRC_FILE"
source "$CONFIG_SRC_FILE"

# نصب تمام پیش‌نیازها
echo "--> Installing all dependencies..."
sed -i -e 's/^#\(.*\/community\)$/\1/' /etc/apk/repositories
apk update
apk add bash nodejs npm git curl mosquitto-clients tzdata openntpd unzip jq

# تنظیم ساعت
echo "--> Setting timezone and syncing clock..."
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
    sed -i 's/\r$//' "$V2RAY_CONFIG_SRC"
    curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
    unzip -o xray.zip -d /usr/local/bin/ && rm xray.zip && chmod +x /usr/local/bin/xray
    
    XRAY_CONFIG_FILE="/etc/xray/config.json"
    mkdir -p /etc/xray
    cp "$V2RAY_CONFIG_SRC" "$XRAY_CONFIG_FILE"
    pm2 delete xray-client > /dev/null 2>&1 || true
    pm2 start /usr/local/bin/xray --name "xray-client" -- -c "$XRAY_CONFIG_FILE"
    
    echo "--> Testing V2Ray proxy connection..."
    sleep 5
    PROXY_PORT=$(jq -r '.inbounds[0].port' "$XRAY_CONFIG_FILE")
    V2RAY_PROXY="socks5h://127.0.0.1:${PROXY_PORT}"
    if curl -s --proxy "$V2RAY_PROXY" --connect-timeout 15 "https://www.google.com" > /dev/null; then
        echo "✅ V2Ray proxy test successful!"
    else
        echo "❌ WARNING: V2Ray proxy test failed. Telegram notifications may not work."
    fi
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

echo ""
echo "--> Final System Time:"
date
echo ""
echo "✅✅✅ Initial Setup Is Complete! ✅✅✅"
echo "To start the tunnel and get a URI, run the following command:"
echo "sh ${INSTALL_DIR}/run-tunnel.sh"