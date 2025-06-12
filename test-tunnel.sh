#!/bin/bash

echo "--> Cleaning up old processes..."
pm2 delete cflare-tunnel > /dev/null 2>&1

LOG_FILE="/root/.pm2/logs/cflare-tunnel-out.log"
if [ -f "$LOG_FILE" ]; then rm "$LOG_FILE"; fi

echo "--> Starting a new tunnel via PM2..."
pm2 start "/usr/local/bin/cloudflared tunnel --url http://localhost:8000" --name "cflare-tunnel"

echo "--> Waiting for log file to be created..."
sleep 5

if [ ! -f "$LOG_FILE" ]; then
    echo "❌ ERROR: Log file was not created. Check PM2 status."
    exit 1
fi

echo "--> Displaying live logs from ${LOG_FILE}"
echo "--> Press Ctrl+C to stop viewing logs."
echo "--------------------------------------------------"

# این دستور لاگ‌ها را به صورت زنده نمایش می‌دهد
tail -f "$LOG_FILE"