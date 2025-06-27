#!/bin/bash
set -e

# =================================================================================
#   IoT Server Smart Tunnel Runner (v11 - The Definitive Collaborative Version)
# =================================================================================

echo "--> Starting Ultimate Tunnel Script..."

# --- بخش ۱: بارگذاری کانفیگ‌های متفرقه ---
INSTALL_DIR="/opt/iot-server"
CONFIG_SRC_FILE="/media/com/command/iot-config.txt"
LOCAL_CONFIG_FILE="${INSTALL_DIR}/iot-config.txt"
if [ -f "$CONFIG_SRC_FILE" ]; then cp "$CONFIG_SRC_FILE" "$LOCAL_CONFIG_FILE"; sed -i 's/\r$//' "$LOCAL_CONFIG_FILE"; fi
if [ -f "$LOCAL_CONFIG_FILE" ]; then source "$LOCAL_CONFIG_FILE"; else echo "ℹ️ NOTE: IoT Config file not found. Notifications will be skipped."; fi


# --- بخش ۲: مدیریت کانفیگ پویا برای Xray ---
echo "--> Checking for new Xray config..."
XRAY_CONFIG_SRC="/media/com/command/v2ray_config.json"
XRAY_LOCAL_CONFIG="/etc/xray/config.json"
if [ -f "$XRAY_CONFIG_SRC" ]; then
    echo "--> New Xray config file found! Applying and restarting Xray service..."
    sed -i 's/\r$//' "$XRAY_CONFIG_SRC"
    mkdir -p /etc/xray
    cp "$XRAY_CONFIG_SRC" "$XRAY_LOCAL_CONFIG"
    # استفاده از دستور بهینه pm2
    pm2 startOrRestart /usr/local/bin/xray --name "xray-client" -- --config "$XRAY_LOCAL_CONFIG"
    sleep 5
else
    echo "--> No new Xray config file found."
fi


# --- بخش ۳: مدیریت کانفیگ پویا برای Sing-box ---
echo "--> Checking for new Sing-box config..."
SINGBOX_CONFIG_SRC="/media/com/command/singbox_config.json"
SINGBOX_LOCAL_CONFIG="/etc/sing-box/config.json"
if [ -f "$SINGBOX_CONFIG_SRC" ]; then
    echo "--> New Sing-box config file found! Applying and restarting Sing-box service..."
    sed -i 's/\r$//' "$SINGBOX_CONFIG_SRC"
    mkdir -p /etc/sing-box
    cp "$SINGBOX_CONFIG_SRC" "$SINGBOX_LOCAL_CONFIG"
    # استفاده از دستور بهینه pm2
    pm2 startOrRestart /usr/local/bin/sing-box --name "singbox-client" -- run -c "$SINGBOX_LOCAL_CONFIG"
    sleep 5
else
    echo "--> No new Sing-box config file found."
fi


# --- بخش ۴: تست هوشمند و انتخاب پراکسی سالم ---
echo "--> Starting proxy health check..."
WORKING_PROXY=""

# تست Xray (فقط در صورتی که در حال اجرا باشد و فایل کانفیگش موجود باشد)
echo "--> [1/2] Testing Xray proxy..."
if pm2 describe xray-client 2>/dev/null | grep -q "status.*online" && [ -f "$XRAY_LOCAL_CONFIG" ]; then
    XRAY_PROXY_PORT=$(jq -r '.inbounds[0].port' "$XRAY_LOCAL_CONFIG")
    XRAY_PROXY="socks5h://127.0.0.1:${XRAY_PROXY_PORT}"
    if curl -s --proxy "$XRAY_PROXY" --connect-timeout 15 "http://example.com" > /dev/null; then
        echo "✅ Xray is working! Using it as the active proxy."
        WORKING_PROXY="$XRAY_PROXY"
    else
        echo "⚠️ Xray is running but connection test failed."
    fi
else
    echo "ℹ️ Xray is not running or has no config. Skipping test."
fi

# اگر پراکسی سالمی پیدا نشده بود (یعنی xray شکست خورد)، به سراغ sing-box میرویم

echo "--> [2/2] Testing Sing-box proxy..."
if pm2 describe singbox-client 2>/dev/null | grep -q "status.*online" && [ -f "$SINGBOX_LOCAL_CONFIG" ]; then
	SINGBOX_PROXY_PORT=$(jq -r '.inbounds[0].port' "$SINGBOX_LOCAL_CONFIG")
	SINGBOX_PROXY="socks5h://127.0.0.1:${SINGBOX_PROXY_PORT}"
	if curl -s --proxy "$SINGBOX_PROXY" --connect-timeout 15 "http://example.com" > /dev/null; then
		echo "✅ Sing-box is working!"
		if [ -z "$WORKING_PROXY" ]; then
			echo "Using it as the active proxy."
			WORKING_PROXY="$SINGBOX_PROXY"
		fi
	else
		echo "⚠️ Sing-box is running but connection test failed."
	fi
else
	echo "ℹ️ Sing-box is not running or has no config. Skipping test."
fi


# بررسی نهایی برای اطمینان از وجود یک پراکسی سالم
if [ -z "$WORKING_PROXY" ]; then
    echo "❌ No working proxy found. Will attempt to start tunnel without proxy."
else
    echo "--> Active proxy for this session is: $WORKING_PROXY"
fi

# --- بخش ۵: راه‌اندازی تونل Cloudflare با پراکسی سالم ---
LOG_FILE="${INSTALL_DIR}/cloudflared.log"
rm -f "$LOG_FILE"
pkill -f cloudflared  true
sleep 1
if [ -n "$WORKING_PROXY" ]; then
    echo "--> Starting Cloudflare Tunnel via the active proxy..."
    /usr/local/bin/cloudflared --proxy-addr "$WORKING_PROXY" tunnel --protocol http2 --url http://localhost:8000 > "$LOG_FILE" 2>&1 &
else
    echo "--> Starting Cloudflare Tunnel directly (no proxy)..."
    /usr/local/bin/cloudflared tunnel --protocol http2 --url http://localhost:8000 > "$LOG_FILE" 2>&1 &
fi
CLOUDFLARED_PID=$!
echo "--> Tunnel process started with PID: ${CLOUDFLARED_PID}."

# --- بخش ۶: حلقه اصلی ناظر و ارسال کامل نوتیفیکیشن ---
NOTIFICATION_SENT=false
while true; do
    if [ ! -d "/proc/$CLOUDFLARED_PID" ]; then
        echo ""
        echo "❌ ERROR: Cloudflare Tunnel process (PID: ${CLOUDFLARED_PID}) has died."
        echo "--> Exiting script to allow PM2 to restart it."
        break
    fi

    if [ "$NOTIFICATION_SENT" = false ]; then
        URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1  true)
        if [ -n "$URI" ]; then
            WSS_URI="wss://${URI#https://}"
            
            # ... (بخش ارسال MQTT بدون تغییر) ...

            # ارسال نوتیفیکیشن تلگرام با پراکسی سالم (در صورت وجود)
            if [ -n "$BOT_TOKEN" ] && [ -n "$CHANNEL_ID" ]; then
                echo "--> Sending and verifying Telegram notification..."
                PROXY_OPTION=""
                if [ -n "$WORKING_PROXY" ]; then
                    PROXY_OPTION="--proxy ${WORKING_PROXY}"
                fi
                MESSAGE="✅ New IoT Server URI Generated:%0A${URI}"
                TELEGRAM_RESPONSE=$(curl -s ${PROXY_OPTION} --connect-timeout 15 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHANNEL_ID}" -d text="${MESSAGE}")
                # ... (بخش چک کردن پاسخ تلگرام بدون تغییر) ...
            fi
            
            echo ""
            echo "✅✅✅ SUCCESS! URI is Ready and Stable! ✅✅✅"
            echo "=================================================="
            echo "HTTP (for browser): ${URI}"
            echo "WSS (for ESP32):    ${WSS_URI}"
            echo "=================================================="
			echo ""
			echo "--> Final System Time:"
			date
			echo ""
            echo "Script is now in silent monitoring mode. Press Ctrl+C to exit if running manually."
            
            NOTIFICATION_SENT=true
        fi
    fi

    sleep 10
done

exit 1