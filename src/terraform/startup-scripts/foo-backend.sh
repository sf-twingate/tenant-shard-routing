#!/bin/bash

# Install and start a simple HTTP server for /foo backend

apt-get update
apt-get install -y python3

# Create a simple HTTP response
cat > /tmp/response.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>${shard_name} - ${service_name}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 600px; margin: 0 auto; text-align: center; }
        .shard { color: #ea4335; font-size: 2em; font-weight: bold; }
        .service { color: #fbbc04; font-size: 1.5em; }
        .info { background: #fff3cd; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .foo { background: #d4edda; padding: 10px; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Shard Demo Backend</h1>
        <div class="shard">${shard_name}</div>
        <div class="service">${service_name} service</div>
        
        <div class="info">
            <h3>Request Information</h3>
            <p><strong>Path:</strong> <span class="foo">/foo</span></p>
            <p><strong>Backend:</strong> ${shard_name}-${service_name}</p>
            <p><strong>Instance:</strong> $(hostname)</p>
            <p><strong>Time:</strong> $(date)</p>
        </div>
        
        <p>✅ This is the <strong>/foo</strong> backend for ${shard_name}. Path-based routing is working correctly!</p>
    </div>
</body>
</html>
EOF

# Create header-forwarding HTTP server
cat > /tmp/header_server.py << 'PYEOF'
#!/usr/bin/env python3
import http.server
import socketserver
import os

class HeaderForwardingHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Send response
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        
        # Forward all x- headers from request to response
        for header, value in self.headers.items():
            if header.lower().startswith('x-'):
                self.send_header(f'req-{header.lower()}', value)
        
        # Add server identification
        self.send_header('x-server-id', '${shard_name}-${service_name}')
        self.end_headers()
        
        # Send the HTML content
        with open('/tmp/response.html', 'rb') as f:
            self.wfile.write(f.read())
    
    def log_message(self, format, *args):
        # Log to stdout
        print(f"{self.address_string()} - - [{self.log_date_time_string()}] {format%args}")

PORT = 80
with socketserver.TCPServer(('', PORT), HeaderForwardingHandler) as httpd:
    print(f'Header-forwarding server running on port {PORT}')
    httpd.serve_forever()
PYEOF

# Kill any existing Python servers
pkill -f "python3.*http.server" || true

# Start header-forwarding HTTP server
python3 /tmp/header_server.py &

# Keep the script running
while true; do
  sleep 60
done