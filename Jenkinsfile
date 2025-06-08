pipeline {
    agent any

    parameters {
        string(name: 'SUBDOMAIN', defaultValue: 'converter', description: 'Enter subdomain like converter')
        string(name: 'PORT', defaultValue: '9092', description: 'Port where Spring Boot app runs')
        string(name: 'EMAIL', defaultValue: 'admin@kpawan.com', description: 'Email for SSL certificate')
    }

    stages {
        stage('Setup Nginx for Subdomain') {
            steps {
                script {
                    def SUBDOMAIN = params.SUBDOMAIN
                    def PORT = params.PORT
                    def EMAIL = params.EMAIL
                    def DOMAIN = "kpawan.com"
                    def FULL_DOMAIN = "${SUBDOMAIN}.${DOMAIN}"

                    def scriptContent = """#!/bin/bash
set -e

DOMAIN="${DOMAIN}"
SUBDOMAIN="${SUBDOMAIN}"
FULL_DOMAIN="${FULL_DOMAIN}"
PORT="${PORT}"
EMAIL="${EMAIL}"

CONFIG_FILE="/etc/nginx/sites-available/\${FULL_DOMAIN}.conf"
SYMLINK="/etc/nginx/sites-enabled/\${FULL_DOMAIN}.conf"

# Step 1: Create webroot config for certbot
sudo mkdir -p /var/www/certbot

sudo tee "\${CONFIG_FILE}" > /dev/null <<EOF
server {
    listen 80;
    server_name \${FULL_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\\\$host\\\$request_uri;
    }
}
EOF

sudo ln -sf "\${CONFIG_FILE}" "\${SYMLINK}"
sudo nginx -t
sudo systemctl reload nginx

# Step 2: Issue SSL certificate
sudo certbot certonly --webroot -w /var/www/certbot -d "\${FULL_DOMAIN}" --non-interactive --agree-tos -m "\${EMAIL}"

# Step 3: Replace config with full SSL reverse proxy
sudo tee "\${CONFIG_FILE}" > /dev/null <<EOF
server {
    listen 80;
    server_name \${FULL_DOMAIN};
    return 301 https://\\\$host\\\$request_uri;
}

server {
    listen 443 ssl;
    server_name \${FULL_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/\${FULL_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/\${FULL_DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:\${PORT};
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
    }
}
EOF

# Final Nginx reload
sudo nginx -t
sudo systemctl reload nginx
"""

                    writeFile file: 'setup_nginx.sh', text: scriptContent
                    sh 'chmod +x setup_nginx.sh'
                    sh './setup_nginx.sh'
                }
            }
        }
    }
}