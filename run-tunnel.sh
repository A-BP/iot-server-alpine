#!/bin/bash
set -e

# =================================================================================
#   IoT Server Smart Tunnel Runner (v12 - English Comments)
# =================================================================================
# This script establishes a resilient Cloudflare tunnel by intelligently selecting
# a working proxy (Xray or Sing-box), and then supervises the tunnel process.
# It is designed to be run by a process manager like pm2 for 24/7 availability.
# =================================================================================


###################################################################################
#                                  HELPER FUNCTIONS
###################################################################################

#
# Smart function to find the correct proxy details from a JSON config file.
# It prioritizes a specifically tagged inbound but falls back to the first one
# in the list for simple configs. It exits with an error for ambiguous configs.
#
# @param {string} $1 - Path to the JSON configuration file.
# @returns {string} The listen address and port, space-separated. Exits on fatal error.
#

find_smart_proxy_details() {
    local config_file="$1"
    local desired_tag="socks-for-tunnel"

    # Step 1: Find ALL SOCKS inbounds from the config file. Do NOT use head -n 1 yet.
    local all_socks_inbounds
    all_socks_inbounds=$(jq -c '.inbounds[] | select(.protocol == "socks" or .type == "socks")' "$config_file" < /dev/null 2>/dev/null)

    # If the result is empty, it means no SOCKS inbounds exist at all.
    if [ -z "$all_socks_inbounds" ]; then
        echo "failed"
        return
    fi

    # Step 2: Now, apply the decision logic based on tags and count.
    local final_inbound=""
    local inbound_count=$(echo "$all_socks_inbounds" | wc -l)

    # Search for a tagged inbound within the complete list.
    local tagged_inbound
    tagged_inbound=$(echo "$all_socks_inbounds" | jq -c 'select(.tag == "'"$desired_tag"'")')

    if [ -n "$tagged_inbound" ]; then
        # Priority 1: A tagged inbound was found. Use the first one if there are multiple.
        final_inbound=$(echo "$tagged_inbound" | head -n 1)
    elif [ "$inbound_count" -gt 1 ]; then
        # Priority 2: Multiple untagged inbounds found. This is an ambiguous error.
        echo "❌ CONFIG ERROR: Multiple SOCKS inbounds found, but none have the required tag: '$desired_tag'." >&2
        echo "failed"
        return
    else
        # Priority 3: Only one SOCKS inbound exists, use it by default.
        final_inbound="$all_socks_inbounds"
    fi

    # Step 3: Extract details from the chosen 'final_inbound' object.
    local listen_addr
    listen_addr=$(echo "$final_inbound" | jq -r '.listen // "127.0.0.1"')
    
    local port
    port=$(echo "$final_inbound" | jq -r '.listen_port // .port')

    # Step 4: Return the final result or the failure signature.
    if [ -n "$port" ]; then
        echo "$listen_addr $port"
    else
        echo "failed"
    fi
}

###################################################################################
#                                 MAIN SCRIPT LOGIC
###################################################################################

echo "--> Starting Ultimate Tunnel Script..."

# --- Section 1: Dynamic Configuration Loading ---
INSTALL_DIR="/opt/iot-server"
CONFIG_SRC_FILE="/media/com/command/iot-config.txt"
LOCAL_CONFIG_FILE="${INSTALL_DIR}/iot-config.txt"
if [ -f "$CONFIG_SRC_FILE" ]; 
	then cp "$CONFIG_SRC_FILE" "$LOCAL_CONFIG_FILE"; 
	sed -i 's/\r$//' "$LOCAL_CONFIG_FILE"; # Remove Windows-style carriage returns
fi
if [ -f "$LOCAL_CONFIG_FILE" ]; then 
	source "$LOCAL_CONFIG_FILE"; 
else
	echo "ℹ️ NOTE: IoT Config file not found. Notifications will be skipped."; 
fi

# --- Section 2: Dynamic Xray Config Management ---
echo "--> Checking for new Xray config..."
XRAY_CONFIG_SRC="/media/com/command/xray_config.json"
XRAY_LOCAL_CONFIG="/etc/xray/config.json"
if [ -f "$XRAY_CONFIG_SRC" ]; then
    echo "--> New Xray config file found! Applying and restarting Xray service..."
    sed -i 's/\r$//' "$XRAY_CONFIG_SRC"
    mkdir -p /etc/xray
    cp "$XRAY_CONFIG_SRC" "$XRAY_LOCAL_CONFIG"
    # Use pm2 to manage the process for resilience (restarts on failure, etc.)
	pm2 delete xray-client || true
    pm2 start /usr/local/bin/xray --name "xray-client" -- run -c "$XRAY_LOCAL_CONFIG"
    sleep 5 # Give the service time to start up
else
    echo "--> No new Xray config file found."
fi

# --- Section 3: Dynamic Sing-box Config Management ---
echo "--> Checking for new Sing-box config..."
SINGBOX_CONFIG_SRC="/media/com/command/singbox_config.json"
SINGBOX_LOCAL_CONFIG="/etc/sing-box/config.json"
if [ -f "$SINGBOX_CONFIG_SRC" ]; then
    echo "--> New Sing-box config file found! Applying and restarting Sing-box service..."
    sed -i 's/\r$//' "$SINGBOX_CONFIG_SRC"
    mkdir -p /etc/sing-box
    cp "$SINGBOX_CONFIG_SRC" "$SINGBOX_LOCAL_CONFIG"
    # Use pm2 for process management
	pm2 delete singbox-client || true
    pm2 start /usr/local/bin/sing-box --name "singbox-client" -- run -c "$SINGBOX_LOCAL_CONFIG"
    sleep 5
else
    echo "--> No new Sing-box config file found."
fi

# --- Section 4: Comprehensive Health Check for ALL Proxies ---
echo "--> Starting comprehensive health check for all proxies..."

# We will store the result of each successful test in a dedicated variable
XRAY_HEALTHY_PROXY=""
SINGBOX_HEALTHY_PROXY=""

# Define an array of reliable and lightweight URLs for health checks
HEALTH_CHECK_URLS=(
    "http://detectportal.firefox.com/success.txt"
    "http://connectivity-check.ubuntu.com"
    "http://www.msftncsi.com/ncsi.txt"
    "http://clients3.google.com/generate_204"
)

# --- [1/2] Comprehensively Testing Xray proxy ---
echo "--> [1/2] Testing Xray proxy..."
if pm2 describe xray-client 2>/dev/null | grep -q "status.*online" && [ -f "$XRAY_LOCAL_CONFIG" ]; then
    proxy_details=$(find_smart_proxy_details "$XRAY_LOCAL_CONFIG")
    if [ "$proxy_details" != "failed" ]; then
        XRAY_LISTEN=$(echo "$proxy_details" | cut -d' ' -f1)
        XRAY_PORT=$(echo "$proxy_details" | cut -d' ' -f2)
        XRAY_PROXY_URI="socks5h://$XRAY_LISTEN:$XRAY_PORT"
        echo "--> Found Xray SOCKS proxy: $XRAY_PROXY_URI. Starting loop test..."

        for TEST_URL in "${HEALTH_CHECK_URLS[@]}"; do
            if curl -s -L --max-time 5 --proxy "$XRAY_PROXY_URI" --connect-timeout 10 "$TEST_URL" > /dev/null; then
                echo "    ✅ SUCCESS: Xray connection confirmed via $TEST_URL"
                XRAY_HEALTHY_PROXY="$XRAY_PROXY_URI" # Store the healthy proxy
                break # Exit the loop for Xray
            fi
        done
    fi
else
    echo "ℹ️ Xray is not running or has no config."
fi
# Final status for Xray
if [ -z "$XRAY_HEALTHY_PROXY" ]; then echo "❌ Xray test FAILED for all URLs."; else echo "✅ Xray test PASSED."; fi


# --- [2/2] Comprehensively Testing Sing-box proxy ---
echo "--> [2/2] Testing Sing-box proxy..."
if pm2 describe singbox-client 2>/dev/null | grep -q "status.*online" && [ -f "$SINGBOX_LOCAL_CONFIG" ]; then
    proxy_details=$(find_smart_proxy_details "$SINGBOX_LOCAL_CONFIG")
    if [ "$proxy_details" != "failed" ]; then
        SINGBOX_LISTEN=$(echo "$proxy_details" | cut -d' ' -f1)
        SINGBOX_PORT=$(echo "$proxy_details" | cut -d' ' -f2)
        SINGBOX_PROXY_URI="socks5h://$SINGBOX_LISTEN:$SINGBOX_PORT"
        echo "--> Found Sing-box SOCKS proxy: $SINGBOX_PROXY_URI. Starting loop test..."

        for TEST_URL in "${HEALTH_CHECK_URLS[@]}"; do
            if curl -s -L --max-time 5 --proxy "$SINGBOX_PROXY_URI" --connect-timeout 10 "$TEST_URL" > /dev/null; then
                echo "    ✅ SUCCESS: Sing-box connection confirmed via $TEST_URL"
                SINGBOX_HEALTHY_PROXY="$SINGBOX_PROXY_URI" # Store the healthy proxy
                break # Exit the loop for Sing-box
            fi
        done
    fi
else
    echo "ℹ️ Sing-box is not running or has no config."
fi
# Final status for Sing-box
if [ -z "$SINGBOX_HEALTHY_PROXY" ]; then echo "❌ Sing-box test FAILED for all URLs."; else echo "✅ Sing-box test PASSED."; fi


# --- Final Decision Block ---
echo "--> Health check complete. Deciding which proxy to use for the tunnel..."
WORKING_PROXY=""
if [ -n "$XRAY_HEALTHY_PROXY" ]; then
    echo "✅ Priority 1: Xray is healthy. Using it for the tunnel."
    WORKING_PROXY="$XRAY_HEALTHY_PROXY"
elif [ -n "$SINGBOX_HEALTHY_PROXY" ]; then
    echo "✅ Priority 2: Sing-box is healthy. Using it for the tunnel."
    WORKING_PROXY="$SINGBOX_HEALTHY_PROXY"
else
    echo "❌ No working proxy found. Will attempt to start tunnel without proxy."
fi

# --- Section 5: Launching Cloudflare Tunnel with the Active Proxy ---
LOG_FILE="${INSTALL_DIR}/cloudflared.log"
rm -f "$LOG_FILE"
pkill -f cloudflared || true
sleep 1

CLOUDFLARED_COMMAND="/usr/local/bin/cloudflared tunnel --protocol http2 --url http://localhost:8000"

if [ -n "$WORKING_PROXY" ]; then
    echo "--> Starting Cloudflare Tunnel via the active proxy..."
	# Prefix the command with the environment variable to limit its scope. This is safer than export/unset.
    # We replace 'socks5h' with 'socks5' as some tools have better support for the latter in env vars.
	https_proxy=${WORKING_PROXY/socks5h/socks5} $CLOUDFLARED_COMMAND > "$LOG_FILE" 2>&1 &
else
    echo "--> Starting Cloudflare Tunnel directly (no proxy)..."
    $CLOUDFLARED_COMMAND > "$LOG_FILE" 2>&1 &
fi

CLOUDFLARED_PID=$!
echo "--> Tunnel process started with PID: ${CLOUDFLARED_PID}."

# --- Section 6: Main Supervisor Loop and Notification Handler ---
NOTIFICATION_SENT=false
while true; do
	 # Crucial check: has the cloudflared process died?
    if [ ! -d "/proc/$CLOUDFLARED_PID" ]; then
        echo ""
        echo "❌ ERROR: Cloudflare Tunnel process (PID: ${CLOUDFLARED_PID}) has died."
        echo "--> Exiting script to allow PM2 to restart it."
        break # Exit the while loop
    fi

	# Only attempt to send a notification if we haven't already sent one.
    if [ "$NOTIFICATION_SENT" = false ]; then
		# Try to find the tunnel URI in the log file.
        URI=$(grep -o 'https://[a-z0-9-]*\.trycloudflare.com' "$LOG_FILE" | head -n 1 || true)
		
        if [ -n "$URI" ]; then
            WSS_URI="wss://${URI#https://}"
            
			# Publish to MQTT if configured
			if [ -n "$MQTT_TOPIC" ]; then
				echo "--> Publishing to MQTT Topic: ${MQTT_TOPIC}"
				mosquitto_pub -h "broker.hivemq.com" -p 1883 -t "$MQTT_TOPIC" -m "$WSS_URI"
			fi

            # Send Telegram notification if configured
            if [ -n "$BOT_TOKEN" ] && [ -n "$CHANNEL_ID" ]; then
                echo "--> Sending and verifying Telegram notification..."
                PROXY_OPTION=""
                if [ -n "$WORKING_PROXY" ]; then
                    PROXY_OPTION="--proxy ${WORKING_PROXY}"
                fi
                MESSAGE="✅ New IoT Server URI Generated:%0A${URI}"
				
                TELEGRAM_RESPONSE=$(curl -s ${PROXY_OPTION} --connect-timeout 15 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHANNEL_ID}" -d text="${MESSAGE}")
                if echo "${TELEGRAM_RESPONSE}" | jq -e '.ok' > /dev/null; then
                    echo "✅ Telegram notification sent successfully!"
                else
                    echo "❌ WARNING: Telegram notification failed."
					ERROR_DESC=$(echo "${TELEGRAM_RESPONSE}" | jq -r '.description')
					echo "--> Telegram API Error: ${ERROR_DESC}"
                fi
            fi
            
            echo ""
            echo "✅✅✅ SUCCESS! URI is Ready and Stable! ✅✅✅"
            echo "=================================================="
            echo "HTTP (for browser): ${URI}"
            echo "WSS (for ESP32):    ${WSS_URI}"
            echo "=================================================="
			echo ""
			echo "--> Final System Time: $(date)"
			echo ""
            echo "Script is now in silent monitoring mode. Press Ctrl+C to exit if running manually."
            
			 # Set the flag to true to prevent sending more notifications.
            NOTIFICATION_SENT=true
        fi
    fi
	
	# Wait before the next check.
    sleep 10
done

# The script will only reach here if the tunnel process dies.
# Exit with an error code to signal failure to the process manager.
exit 1