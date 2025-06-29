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
    local desired_tag="socks-for-tunnel"  # The specific tag we are looking for in the inbounds.

    # --- Step 1: Validate the config file and inbound count ---
    local inbound_count
    inbound_count=$(jq '.inbounds | length' "$config_file")
    if [ "$inbound_count" -eq 0 ]; then
        echo "❌ ERROR: No 'inbounds' found in the config file: $config_file" >&2
        return 1
    fi

    # --- Step 2: Set the default proxy to the first inbound in the list ---
    local default_listen default_port
    # Read the 'listen' address. Use '127.0.0.1' as a fallback if the field is not specified (jq's // operator).
    default_listen=$(jq -r '.inbounds[0].listen // "127.0.0.1"' "$config_file")
    default_port=$(jq -r '.inbounds[0].port' "$config_file")

    # --- Step 3: Search for the definitively tagged inbound ---
    local tagged_inbound_json
    # Find the first inbound object that has the desired tag.
    tagged_inbound_json=$(jq -r '.inbounds[] | select(.tag == "'"$desired_tag"'")' "$config_file")

    # --- Step 4: Decision logic ---
    local final_listen="$default_listen"
    local final_port="$default_port"

    if [ -n "$tagged_inbound_json" ]; then
        # If a tagged inbound was found, it overrides the default and becomes our definitive choice.
        echo "--> inbound با تگ ویژه ('$desired_tag') پیدا شد. از آن استفاده می‌شود." >&2
        final_listen=$(echo "$tagged_inbound_json" | jq -r '.listen // "127.0.0.1"')
        final_port=$(echo "$tagged_inbound_json" | jq -r '.port')
    elif [ "$inbound_count" -gt 1 ]; then
        # If no tagged inbound was found AND there are multiple inbounds, this is an ambiguous state.
        # We must halt to prevent using the wrong proxy.
        echo "❌❌❌ CONFIGURATION ERROR ❌❌❌" >&2
        echo "Script halted. Your config file '$config_file' has multiple 'inbounds' but none have the required tag." >&2
        echo "This is an ambiguous situation, and the script cannot safely choose a proxy." >&2
        echo "" >&2
        # Use a heredoc (cat <<EOF) for a clean, multi-line help message.
        cat >&2 <<EOF
✅ SOLUTION: Add a 'tag' to your desired inbound in the config file.
Example:
  "inbounds": [
    {
      "port": ${default_port},
      "listen": "${default_listen}",
      "protocol": "socks",
      ...
      "tag": "${desired_tag}"  // <-- Add this line
    },
    ...
  ]
EOF
        return 1 # Exit the function with a non-zero status code to indicate failure.
    fi

    # --- Step 5: Return the final values ---
    # Print the listen address and port, space-separated, to stdout. This allows the caller
    # to capture the output easily using the 'read' command.
    echo "$final_listen $final_port"
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
    pm2 start /usr/local/bin/xray --name "xray-client" -- --config "$XRAY_LOCAL_CONFIG"
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

# --- Section 4: Smart Proxy Health Check and Selection ---
echo "--> Starting proxy health check..."
WORKING_PROXY=""

# Test Xray (only if the process is online and its config file exists)
echo "--> [1/2] Testing Xray proxy..."
if pm2 describe xray-client 2>/dev/null | grep -q "status.*online" && [ -f "$XRAY_LOCAL_CONFIG" ]; then
	# Call the smart function to get proxy details
	proxy_details=$(find_smart_proxy_details "$XRAY_LOCAL_CONFIG")
	if [ $? -ne 0 ]; then
        # The function printed an error message and exited with a non-zero code. Halt the script.
        exit 1
    fi
	# Read the space-separated output into distinct variables
    read XRAY_LISTEN  XRAY_PROXY_PORT <<< "$proxy_details"
	
	XRAY_PROXY="socks5h://${XRAY_LISTEN}:${ XRAY_PROXY_PORT}"
    if curl -s -m 5 --proxy "$XRAY_PROXY" --connect-timeout 15 "http://example.com" > /dev/null; then
        echo "✅ Xray is working! Using it as the active proxy."
        WORKING_PROXY="$XRAY_PROXY"
    else
        echo "⚠️ Xray is running but connection test failed."
    fi
else
    echo "ℹ️ Xray is not running or has no config. Skipping test."
fi

# If no working proxy has been found yet, test Sing-box as a fallback.
echo "--> [2/2] Testing Sing-box proxy..."
if pm2 describe singbox-client 2>/dev/null | grep -q "status.*online" && [ -f "$SINGBOX_LOCAL_CONFIG" ]; then
	proxy_details=$(find_smart_proxy_details "$SINGBOX_LOCAL_CONFIG")
	if [ $? -ne 0 ]; then
        exit 1
    fi
	read SINGBOX_LISTEN SINGBOX_PROXY_PORT <<< "$proxy_details"
	
    SINGBOX_PROXY="socks5h://${SINGBOX_LISTEN}:${SINGBOX_PROXY_PORT}"
	if curl -s -m 5 --proxy "$SINGBOX_PROXY" --connect-timeout 15 "http://example.com" > /dev/null; then
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

# Final check to see if we found a usable proxy.
if [ -z "$WORKING_PROXY" ]; then
    echo "❌ No working proxy found. Will attempt to start tunnel without proxy."
else
    echo "--> Active proxy for this session is: $WORKING_PROXY"
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