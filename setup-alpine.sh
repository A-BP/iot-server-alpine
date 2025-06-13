#!/bin/bash
set -e

# ==============================================================================
#   IoT Server Initial Setup Script (Final Version)
# ==============================================================================

echo "### Starting IoT Server One-Time Setup ###"

# خواندن و اصلاح فایل iot-config.txt
CONFIG_SRC_FILE="/media/com/command/iot-config.txt"
if [ ! -f "$CONFIG_SRC_FILE" ]; then echo "❌ ERROR: Config file not found at ${CONFIG_SRC_FILE}!"; exit 1; fi
echo "--> Converting and reading configuration from ${CONFIG_SRC_FILE}..."
sed -i 's/\r$//' "$CONFIG_SRC_FILE"
source "$CONFIG_SRC_FILE"

# فعال‌سازی مخزن Community و به‌روزرسانی
echo "--> Enabling 'community' repository and updating..."
sed -i -e 's/^#\(.*\/community\)$/\1/' /etc/apk/repositories
apk update

# نصب تمام پیش‌نیازها (شامل jq برای تست تلگرام)
echo "--> Installing all dependencies..."
apk add bash nodejs npm git curl mosquitto-clients tzdata openntpd unzip jq

# تنظیم ساعت و منطقه زمانی
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
echo "✅✅✅ Initial Setup Is Complete! ✅✅✅"
echo "To start the tunnel and get a URI, run the following command:"
echo "sh ${INSTALL_DIR}/run-tunnel.sh"