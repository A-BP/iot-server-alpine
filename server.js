const express = require('express');
const WebSocket = require('ws');
const app = express();
const port = 8000;

// Serve the HTML file from the 'public' directory
app.use(express.static('public'));

// Start the HTTP server
const server = app.listen(port, () => {
    console.log(`Server running at http://localhost:${port}`);
});

// WebSocket server attached to the HTTP server
const wss = new WebSocket.Server({ server });

// Variable to keep track of the ESP32 WebSocket client connection
// We initialize it to null. When the ESP32 connects and sends sensor data,
// we'll store its specific 'ws' object here.
let esp32Client = null;

wss.on('connection', (ws) => {
    console.log('✅ New client connected');

    // Add a close handler for *this specific* client connection
    ws.on('close', () => {
        console.log('❌ Client disconnected');
        // If the disconnected client was the ESP32, clear the reference
        if (ws === esp32Client) {
            console.log('🚫 ESP32 client disconnected. Commands cannot be sent.');
            esp32Client = null; // Set the reference back to null
        }
    });

    // Handle messages received from *this specific* client
    ws.on('message', (message) => {
        // WebSocket messages can be Buffer, ArrayBuffer, or String depending on the data
        // We expect text messages (JSON strings)
        const messageString = message.toString(); // Ensure it's a string for JSON parsing

        console.log(`📩 Received: ${messageString}`);

        try {
            const parsedMessage = JSON.parse(messageString); // Attempt to parse the message as JSON

            // Check the 'type' field of the parsed JSON message
            if (parsedMessage.type === 'sensor_data') {
                console.log('📊 Received sensor data from potential ESP32');
                // If this is the first 'sensor_data' message received, assume this client is the ESP32
                if (esp32Client === null) {
                    esp32Client = ws;
                    console.log('💡 ESP32 client identified by sensor_data message.');
                    // Optionally send a status back to the HTML clients that ESP32 is online
                    wss.clients.forEach((client) => {
                         if (client.readyState === WebSocket.OPEN) {
                             client.send(JSON.stringify({ type: 'status_update', content: '✅ ESP32 is now online.' }));
                         }
                     });
                }

                // Broadcast sensor data to all *other* connected clients (presumably HTML dashboards)
                // The HTML client's onmessage handler knows how to display 'sensor_data'
                wss.clients.forEach((client) => {
                    // Don't send the sensor data back to the sender (the ESP32 itself)
                    if (client !== ws && client.readyState === WebSocket.OPEN) {
                        client.send(messageString); // Send the original JSON string received
                    }
                });
                console.log('Sent sensor data to HTML clients.');


            } else if (parsedMessage.type === 'command') {
                console.log(`🕹️ Received command: ${parsedMessage.content}`);
                // This command message is expected from an HTML client.
                // We need to forward it to the ESP32 client if it's connected.
                if (esp32Client && esp32Client.readyState === WebSocket.OPEN) {
                    // Forward the original JSON command string to the ESP32
                    esp32Client.send(messageString);
                    console.log('➡️ Forwarded command to ESP32.');
                     // Optionally send a status update back to the sender HTML client
                     ws.send(JSON.stringify({ type: 'status_update', content: `✅ Command sent to ESP32: ${parsedMessage.content}`}));
			} else {
                    console.log('❗ ESP32 client not connected. Cannot send command.');
                    // Send a status update back to the sender HTML client
                    ws.send(JSON.stringify({ type: 'status_update', content: '❗️ ESP32 not connected. Cannot send command.' }));
                }

            } else if (parsedMessage.type === 'chat_message') {
                console.log(`💬 Received chat message: ${parsedMessage.content}`);
                // This chat message is expected from an HTML client.
                // Broadcast the chat message to all *other* connected clients (presumably HTML dashboards)
                // We assume ESP32 does NOT need chat messages.
                wss.clients.forEach((client) => {
                    // Don't send the message back to the sender HTML client AND don't send to the ESP32 client (if connected)
                   // //  //client !== ws && client !== esp32Client && client.readyState === WebSocket.OPEN
                    if (client !== ws && client.readyState === WebSocket.OPEN) {
                         client.send(messageString); // Send the original JSON string
                    }
                });
                 console.log('Broadcast chat message to other HTML clients.');
                 // Optionally send a status update back to the sender HTML client
                 // ws.send(JSON.stringify({ type: 'status_update', content: 'Your message was broadcast.' }));


            } else {
                // Handle other valid JSON messages with unknown types
                console.log(`❓ Received JSON message with unknown type: ${parsedMessage.type}`);
                 // Optionally send an error/status back to the sender
                 ws.send(JSON.stringify({ type: 'status_update', content: `❓ Server received JSON with unknown type: ${parsedMessage.type}` }));
            }

        } catch (e) {
            // If JSON parsing fails, it means the message was not a valid JSON string
            console.warn(`⚠️ Received non-JSON message or failed to parse JSON: ${messageString}`);
            // Decide what to do with non-JSON messages. In this setup, they are unexpected.
            // We can ignore them or send an error back to the sender.
            ws.send(JSON.stringify({ type: 'status_update', content: '❗ Server received non-JSON message.' }));
        }
    });

    // Optional: Send a welcome message or initial status update to the newly connected client
    // This message will be handled by the client's onmessage, it should check the type.
    // ws.send(JSON.stringify({ type: 'status_update', content: '✅ Server online. Waiting for connections.' }));
});

// Optional: Handle server closing
server.on('close', () => {
    console.log('HTTP server closing');
    // Close all WebSocket connections gracefully
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.close(1000, 'Server shutting down');
        }
    });
});
