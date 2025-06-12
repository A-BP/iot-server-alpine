#!/bin/bash
set -e

echo "====================================================="
echo "   Interactive IoT Server Setup Script for Alpine    "
echo "====================================================="
echo ""

# --- بخش جدید: پرسیدن سوالات شخصی‌سازی ---
echo "Please provide the following details for your personalized setup."
echo "These will be saved in /opt/iot-server/.env for future use."
echo ""

# پرسیدن تاپیک MQTT با یک مقدار پیش‌فرض
read -p "Enter a unique MQTT Topic (e.g., user/myhome/uri): " MQTT_TOPIC
MQTT_TOPIC=${MQTT_TOPIC:-"default/topic/uri"} # اگر کاربر چیزی وارد نکرد، از مقدار پیش‌فرض استفاده می‌شود

# پرسیدن توکن ربات تلگرام
read -p "Enter your Telegram Bot Token: " BOT_TOKEN

# پرسیدن شناسه کانال یا کاربر تلگرام
read -p "Enter your Telegram Channel/Chat ID (e.g., @MyChannel or a numeric ID): " CHANNEL_ID

echo ""
echo "Configuration received. Starting installation..."
sleep 2
# ---------------------------------------------

# --- مراحل نصب مانند قبل ادامه می‌یابد ---
# ... (تمام مراحل نصب ۱ تا ۷ دقیقاً مانند قبل باقی می‌مانند) ...
echo "--> Enabling 'community' repository and updating..."
sed -i -e 's/^#\(.*\/community\)$/\1/' /etc/apk/repositories
apk update
echo "--> Installing dependencies..."
apk add bash nodejs npm git curl mosquitto-clients

echo "--> Installing PM2..."
npm install -g pm2

echo "--> Installing Cloudflare Tunnel..."
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
mv cloudflared /usr/local/bin/

GITHUB_REPO_URL="https://github.com/A-BP/iot-server-alpine.git"
INSTALL_DIR="/opt/iot-server"
echo "--> Cloning server code from GitHub..."
rm -rf "${INSTALL_DIR}"
git clone "${GITHUB_REPO_URL}" "${INSTALL_DIR}"
if [ ! -d "${INSTALL_DIR}" ]; then echo "❌ ERROR: Failed to clone repository."; exit 1; fi

cd "${INSTALL_DIR}" && npm install

# --- بخش جدید: ذخیره کردن تنظیمات در فایل .env ---
echo "--> Saving your personalized configuration..."
CONFIG_FILE="${INSTALL_DIR}/.env"
echo "MQTT_TOPIC=${MQTT_TOPIC}" > "$CONFIG_FILE"
echo "BOT_TOKEN=${BOT_TOKEN}" >> "$CONFIG_FILE"
echo "CHANNEL_ID=${CHANNEL_ID}" >> "$CONFIG_FILE"
# ----------------------------------------------------

echo "--> Starting Node.js application with PM2..."
pm2 delete iot-app > /dev/null 2>&1 || true
pm2 start server.js --name "iot-app" --cwd "${INSTALL_DIR}"

echo "--> Generating the first URI..."
chmod +x get-new-uri-alpine.sh
./get-new-uri-alpine.sh

echo "--> Configuring services to run on system startup..."
pm2 save
pm2 startup openrc -u root --hp /root

echo ""
echo "✅✅✅ Initial Setup Is Complete! ✅✅✅"