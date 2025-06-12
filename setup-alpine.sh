#!/bin/bash
set -e

echo "========================================================="
echo "   IoT Server Setup via Config File (Final Custom Path)  "
echo "========================================================="
echo ""

# --- خواندن تنظیمات از مسیر جدید شما روی فلش ---
# !! تنها تغییر در این خط است !!
CONFIG_SRC_FILE="/media/usb/command/iot-config.txt"
# ----------------------------------------------------

INSTALL_DIR="/opt/iot-server"
echo "--> Looking for configuration file at ${CONFIG_SRC_FILE}..."

# بررسی می‌کنیم که آیا فایل تنظیمات در مسیر جدید وجود دارد یا خیر
if [ ! -f "$CONFIG_SRC_FILE" ]; then
    echo "❌ CRITICAL ERROR: Configuration file not found at '${CONFIG_SRC_FILE}'!"
    echo "Please ensure 'iot-config.txt' exists inside the 'command' folder on your USB drive."
    exit 1
fi

echo "--> Configuration file found. Starting installation..."
sleep 2

# --- مراحل نصب مانند قبل ادامه می‌یابد ---
sed -i -e 's/^#\(.*\/community\)$/\1/' /etc/apk/repositories
apk update
apk add bash nodejs npm git curl mosquitto-clients
npm install -g pm2
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
mv cloudflared /usr/local/bin/

GITHUB_REPO_URL="https://github.com/A-BP/iot-server-alpine.git"
rm -rf "${INSTALL_DIR}"
git clone "${GITHUB_REPO_URL}" "${INSTALL_DIR}"
cd "${INSTALL_DIR}" && npm install

# --- کپی کردن فایل کانفیگ به پوشه پروژه ---
echo "--> Copying your configuration to the project directory..."
cp "$CONFIG_SRC_FILE" "${INSTALL_DIR}/.env"

# --- راه‌اندازی سرویس‌ها ---
pm2 delete iot-app > /dev/null 2>&1 || true
pm2 start server.js --name "iot-app" --cwd "${INSTALL_DIR}"
chmod +x get-new-uri-alpine.sh
./get-new-uri-alpine.sh
pm2 save
pm2 startup openrc -u root --hp /root

echo ""
echo "✅✅✅ Initial Setup Is Complete! ✅✅✅"