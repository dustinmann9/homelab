#!/bin/bash
# setup-recipe-book-api.sh
# Sets up the Recipe Book API environment on the recipes server
# Run with: sudo ./setup-recipe-book-api.sh

set -e

echo "=== Recipe Book API Setup ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo"
    exit 1
fi

echo ""
echo "1. Installing Java 21..."
apt install -y openjdk-21-jre-headless
java -version

echo ""
echo "2. Creating application directory and user..."
mkdir -p /opt/recipe-book
if ! id "recipeapp" &>/dev/null; then
    useradd -r -s /bin/false recipeapp
    echo "   Created recipeapp user"
else
    echo "   recipeapp user already exists"
fi
chown recipeapp:recipeapp /opt/recipe-book

echo ""
echo "3. Creating systemd service..."
cat > /etc/systemd/system/recipe-book.service << 'EOF'
[Unit]
Description=Recipe Book API
After=network.target

[Service]
Type=simple
User=recipeapp
Group=recipeapp
WorkingDirectory=/opt/recipe-book
ExecStart=/usr/bin/java -jar /opt/recipe-book/recipe-book-api.jar
Restart=on-failure
RestartSec=10

# Logging
StandardOutput=journal
StandardError=journal

# Environment
Environment="SPRING_PROFILES_ACTIVE=prod,sqlite"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo "   Service file created: /etc/systemd/system/recipe-book.service"

echo ""
echo "4. Updating nginx configuration..."

# Backup existing config
cp /etc/nginx/sites-available/recipes.home /etc/nginx/sites-available/recipes.home.bak

# Check if API location block already exists
if grep -q "location /api/" /etc/nginx/sites-available/recipes.home; then
    echo "   API proxy block already exists in nginx config"
else
    # Insert API and images proxy blocks before the existing location / block
    sed -i '/location \/ {/i\
    # API proxy\
    location /api/ {\
        proxy_pass http://127.0.0.1:9002;\
        proxy_http_version 1.1;\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto $scheme;\
        proxy_read_timeout 90;\
    }\
\
    # Images served by Spring Boot\
    location /images/ {\
        proxy_pass http://127.0.0.1:9002;\
        proxy_http_version 1.1;\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto $scheme;\
    }\
' /etc/nginx/sites-available/recipes.home
    echo "   Added API proxy block to nginx config"
fi

# Test nginx config
if nginx -t; then
    systemctl reload nginx
    echo "   nginx reloaded successfully"
else
    echo "   ERROR: nginx config test failed!"
    echo "   Restoring backup..."
    cp /etc/nginx/sites-available/recipes.home.bak /etc/nginx/sites-available/recipes.home
    exit 1
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Deploy JAR to /opt/recipe-book/recipe-book-api.jar"
echo "  2. Copy SQLite database to /opt/recipe-book/sqlite.db"
echo "  3. Set permissions: sudo chown recipeapp:recipeapp /opt/recipe-book/*"
echo "  4. Start service: sudo systemctl start recipe-book"
echo "  5. Enable on boot: sudo systemctl enable recipe-book"
echo "  6. Check status: sudo systemctl status recipe-book"
echo "  7. View logs: sudo journalctl -u recipe-book -f"
echo ""
