#!/bin/bash
set -e

echo "====================================================="
echo "   IoT Server Initial Setup Script for Alpine (v9)   "
echo "====================================================="

# مراحل ۱ تا ۷ بدون هیچ تغییری باقی می‌مانند
echo "--> Step 1-7: Installing all dependencies and setting up the app..."
sed -i -e 's/^#\(.*\/community\)$/\1/' /etc/apk/repositories
apk update
apk add bash nodejs npm git curl
npm install -g pm2
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
mv cloudflared /usr/local/bin/

GITHUB_REPO_URL="https://github.com/A-BP/iot-server-alpine.git"
INSTALL_DIR="/opt/iot-server"
rm -rf "${INSTALL_DIR}"
git clone "${GITHUB_REPO_URL}" "${INSTALL_DIR}"
if [ ! -d "${INSTALL_DIR}" ]; then echo "❌ ERROR: Failed to clone repository."; exit 1; fi
cd "${INSTALL_DIR}" && npm install
pm2 delete iot-app > /dev/null 2>&1 || true
pm2 start server.js --name "iot-app" --cwd "${INSTALL_DIR}"

# --- تغییر کلیدی: جابجایی مراحل ۸ و ۹ ---

# مرحله ۸ (جدید): تنظیم PM2 برای استارتاپ
echo "--> Step 8 of 9: Configuring Node.js app to run on system startup..."
pm2 save
# این دستور خروجی زیادی تولید می‌کند که ما می‌خواهیم قبل از نمایش URI باشد
pm2 startup openrc -u root --hp /root

# مرحله ۹ (جدید): اجرای اسکریپت دریافت URI به عنوان آخرین مرحله
echo "--> Step 9 of 9: Generating the final URI..."
cd "${INSTALL_DIR}"
chmod +x get-new-uri-alpine.sh
# چون این آخرین دستور است، خروجی آن در انتهای صفحه باقی می‌ماند
./get-new-uri-alpine.sh

echo ""
echo "✅✅✅ Initial Setup Is Complete! ✅✅✅"