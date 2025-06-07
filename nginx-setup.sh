#!/bin/bash

set -e

DOMAIN="kpawan.com"
JENKINS_SUB="jenkins.kpawan.com"
SPRING_PORT=9091
JENKINS_PORT=8080
EMAIL="you@example.com"  # Change this

echo "🔍 Detecting OS..."

OS_ID="unknown"
if [ "$(uname)" == "Darwin" ]; then
    OS_ID="mac"
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS_ID=$DISTRIB_ID
    OS_ID=$(echo "$OS_ID" | tr '[:upper:]' '[:lower:]')
elif [ -f /etc/debian_version ]; then
    OS_ID="debian"
elif [ -f /etc/redhat-release ]; then
    OS_ID="rhel"
fi

if [ "$OS_ID" == "unknown" ]; then
    echo "❌ Unsupported or undetected OS."
    exit 1
fi

echo "🖥️ Detected OS: $OS_ID"

# Relaunch with sudo if not root and NOT macOS
if [[ "$EUID" -ne 0 && "$OS_ID" != "mac" ]]; then
  echo "❌ Not running as root. Asking for sudo password..."
  exec sudo bash "$0" "$@"
fi

echo "🔍 Checking Nginx installation..."
if ! command -v nginx &>/dev/null; then
    echo "⚠️ Nginx not found, installing..."
    if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
        apt-get update -y
        apt-get install -y nginx
        systemctl enable --now nginx
    elif [ "$OS_ID" == "mac" ]; then
        if ! command -v brew &>/dev/null; then
            echo "🍺 Homebrew not found. Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
        fi
        brew install nginx
    else
        echo "❌ Nginx installation not supported for OS: $OS_ID"
        exit 1
    fi
else
    echo "✅ Nginx is already installed."
fi

echo "🔐 Installing Certbot for SSL..."
if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
    apt-get install -y certbot python3-certbot-nginx
elif [ "$OS_ID" == "mac" ]; then
    if ! command -v brew &>/dev/null; then
        echo "🍺 Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
    fi
    brew install certbot
else
    echo "❌ Certbot installation not supported for OS: $OS_ID"
    exit 1
fi

echo "✅ Certbot installed."

# Setup nginx config path & folders
if [ "$OS_ID" = "mac" ]; then
    NGINX_CONF_DIR="$(brew --prefix)/etc/nginx"
    SITES_AVAILABLE="$NGINX_CONF_DIR/sites-available"
    SITES_ENABLED="$NGINX_CONF_DIR/sites-enabled"

    mkdir -p "$SITES_AVAILABLE"
    mkdir -p "$SITES_ENABLED"

    CONFIG_PATH="$SITES_AVAILABLE/${DOMAIN}.conf"

    # Symlink config into sites-enabled
    ln -sf "$CONFIG_PATH" "$SITES_ENABLED/${DOMAIN}.conf"

    # Append include directive if missing
    if ! grep -q "include sites-enabled/\*\.conf;" "$NGINX_CONF_DIR/nginx.conf"; then
        echo "include sites-enabled/*.conf;" >> "$NGINX_CONF_DIR/nginx.conf"
    fi
else
    SITES_AVAILABLE="/etc/nginx/sites-available"
    SITES_ENABLED="/etc/nginx/sites-enabled"

    mkdir -p "$SITES_AVAILABLE"
    mkdir -p "$SITES_ENABLED"

    CONFIG_PATH="$SITES_AVAILABLE/${DOMAIN}.conf"
    ln -sf "$CONFIG_PATH" "$SITES_ENABLED/${DOMAIN}.conf"
fi

echo "🌐 Writing nginx config to $CONFIG_PATH..."

cat <<EOF > "$CONFIG_PATH"
server {
    listen 80;
    server_name $DOMAIN $JENKINS_SUB;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:$SPRING_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl;
    server_name $JENKINS_SUB;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:$JENKINS_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

echo "✅ Nginx config created and enabled."

echo "📡 Obtaining SSL certificate from Let's Encrypt..."
#certbot --nginx -d "$DOMAIN" -d "$JENKINS_SUB" --non-interactive --agree-tos -m "$EMAIL" --redirect

if [ "$OS_ID" = "mac" ]; then
    sudo certbot --nginx -d "$DOMAIN" -d "$JENKINS_SUB" --non-interactive --agree-tos -m "$EMAIL" --redirect
else
    certbot --nginx -d "$DOMAIN" -d "$JENKINS_SUB" --non-interactive --agree-tos -m "$EMAIL" --redirect
fi

echo "🔁 Testing and reloading Nginx..."
if nginx -t; then
    if [ "$OS_ID" = "mac" ]; then
        brew services restart nginx
    else
        systemctl reload nginx
    fi
else
    echo "❌ Nginx configuration test failed."
    exit 1
fi

echo "✅ Nginx reverse proxy with SSL setup complete."