#!/bin/bash
set -e

DOMAIN="kpawan.com"
JENKINS_SUB="jenkins.kpawan.com"
SPRING_PORT=9091
JENKINS_PORT=8080
EMAIL="pawan@gmail.com"  # Change this

echo "🔍 Detecting operating system..."
OS=""
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
    else
        echo "❌ Unsupported Linux distro"
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="mac"
else
    echo "❌ Unsupported OS: $OSTYPE"
    exit 1
fi
echo "🖥️ Detected OS: $OS"

# Relaunch with sudo if not root and NOT macOS
if [[ "$EUID" -ne 0 && "$OS" != "mac" ]]; then
  echo "❌ Not running as root. Re-launching with sudo..."
  exec sudo bash "$0" "$@"
fi

install_package() {
    local name="$1"
    local check_cmd="$2"
    local install_cmd="$3"
    echo -n "🔍 Checking for $name... "
    if eval "$check_cmd" &>/dev/null; then
        echo "✅ Already installed."
    else
        echo "📦 Installing $name..."
        eval "$install_cmd"
        echo "✅ Installed $name."
    fi
}

# Create Jenkins user on Linux if missing
if [[ "$OS" == "debian" || "$OS" == "rhel" ]]; then
    if id -u jenkins &>/dev/null; then
        echo "👤 User 'jenkins' exists."
    else
        echo "👤 Creating user 'jenkins'..."
        useradd -m -s /bin/bash jenkins
    fi
fi

# Install packages and repos per OS
case "$OS" in
  debian)
    echo "📦 Updating apt package index..."
    apt-get update -y

    install_package "Docker" "command -v docker" "apt-get install -y docker.io && systemctl enable docker"
    install_package "curl" "command -v curl" "apt-get install -y curl"
    install_package "gnupg2" "command -v gpg" "apt-get install -y gnupg2"
    install_package "openjdk-17-jdk" "java -version" "apt-get install -y openjdk-17-jdk"
    install_package "maven" "command -v mvn" "apt-get install -y maven"
    install_package "nginx" "command -v nginx" "apt-get install -y nginx && systemctl enable nginx"
    install_package "certbot" "command -v certbot" "apt-get install -y certbot python3-certbot-nginx"

    # Jenkins repo & install
    if ! command -v jenkins &>/dev/null; then
      echo "📦 Adding Jenkins repo and installing Jenkins..."
      curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
      apt-get update -y
      apt-get install -y jenkins
      systemctl enable jenkins
    else
      echo "✅ Jenkins already installed."
    fi

    # Add jenkins to docker group
    echo "🔐 Adding Jenkins user to Docker group..."
    if id -nG jenkins | grep -qw docker; then
        echo "✅ Jenkins user is already in the Docker group."
    else
        usermod -aG docker jenkins
        echo "🔁 Restarting Jenkins for group changes to take effect..."
        systemctl restart jenkins
        echo "⚠️ Jenkins restarted — please re-run the script after this."
        exit 1
    fi
    ;;

  rhel)
    echo "📦 Enabling EPEL and updating system..."
    yum install -y epel-release
    yum update -y

    install_package "Docker" "command -v docker" "yum install -y docker && systemctl enable docker"
    install_package "maven" "command -v mvn" "yum install -y maven"
    install_package "nginx" "command -v nginx" "yum install -y nginx && systemctl enable nginx"
    install_package "certbot" "command -v certbot" "yum install -y certbot python3-certbot-nginx"

    # Jenkins repo & install
    if ! command -v jenkins &>/dev/null; then
      echo "📦 Adding Jenkins repo and installing Jenkins..."
      wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
      rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
      yum install -y java-17-openjdk jenkins
      systemctl enable jenkins
    else
      echo "✅ Jenkins already installed."
    fi

    # Add jenkins to docker group
    echo "🔐 Adding Jenkins user to Docker group..."
    if id -nG jenkins | grep -qw docker; then
        echo "✅ Jenkins user is already in the Docker group."
    else
        usermod -aG docker jenkins
        echo "🔁 Restarting Jenkins for group changes to take effect..."
        systemctl restart jenkins
        echo "⚠️ Jenkins restarted — please re-run the script after this."
        exit 1
    fi
    ;;

  mac)
    # Install Homebrew if missing
    if ! command -v brew &>/dev/null; then
        echo "🍺 Installing Homebrew..."
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
    fi

    install_package "Docker" "command -v docker" "brew install --cask docker"
    install_package "Jenkins LTS" "brew list | grep -qw jenkins-lts" "brew install jenkins-lts"
    install_package "Maven" "command -v mvn" "brew install maven"
    install_package "Nginx" "command -v nginx" "brew install nginx"
    install_package "Certbot" "command -v certbot" "brew install certbot"

    echo "⚠️ On macOS, adding Jenkins user to docker group is not applicable."
    ;;
esac

# Start services depending on OS
echo "🚀 Starting Jenkins, Docker, and Nginx services..."
case "$OS" in
  debian|rhel)
    systemctl stop jenkins
    systemctl stop docker
    systemctl stop nginx
    systemctl start jenkins
    systemctl start docker
    systemctl start nginx
    ;;
  mac)
    echo "🚀 Starting Jenkins and Nginx services via brew..."
    brew services stop jenkins-lts
    brew services stop nginx
    brew services start jenkins-lts
    brew services start nginx

    echo "🚀 Launching Docker Desktop..."
    open -a Docker

    echo "⌛ Waiting for Docker to start..."
    while ! docker info >/dev/null 2>&1; do
      sleep 2
      echo "⏳ Waiting for Docker daemon to be ready..."
    done

    echo "✅ Docker is running."
    ;;
esac

echo "🔐 Obtaining SSL certificate from Let's Encrypt..."
CERT_EXISTS=false
if [[ "$OS" == "mac" ]]; then
  CERT_PATH="/usr/local/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
else
  CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
fi
if [ ! -f "$CERT_PATH" ]; then
  if [[ "$OS" == "mac" ]]; then
    sudo certbot --nginx -d "$DOMAIN" -d "$JENKINS_SUB" --non-interactive --agree-tos -m "$EMAIL" --redirect
  else
    certbot --nginx -d "$DOMAIN" -d "$JENKINS_SUB" --non-interactive --agree-tos -m "$EMAIL" --redirect
  fi
else
  echo "🔐 Certificates already exist, skipping certbot."
fi

# Setup nginx config path & folders
if [[ "$OS" == "mac" ]]; then
    NGINX_CONF_DIR="$(brew --prefix)/etc/nginx"
    SITES_AVAILABLE="$NGINX_CONF_DIR/sites-available"
    SITES_ENABLED="$NGINX_CONF_DIR/sites-enabled"
    mkdir -p "$SITES_AVAILABLE" "$SITES_ENABLED"
    CONFIG_PATH="$SITES_AVAILABLE/${DOMAIN}.conf"
    ln -sf "$CONFIG_PATH" "$SITES_ENABLED/${DOMAIN}.conf"
    # Append include directive if missing
    if ! grep -q "include sites-enabled/\*\.conf;" "$NGINX_CONF_DIR/nginx.conf"; then
        echo "include sites-enabled/*.conf;" >> "$NGINX_CONF_DIR/nginx.conf"
    fi
else
    SITES_AVAILABLE="/etc/nginx/sites-available"
    SITES_ENABLED="/etc/nginx/sites-enabled"
    mkdir -p "$SITES_AVAILABLE" "$SITES_ENABLED"
    CONFIG_PATH="$SITES_AVAILABLE/${DOMAIN}.conf"
    ln -sf "$CONFIG_PATH" "$SITES_ENABLED/${DOMAIN}.conf"
fi

sudo rm -f /etc/nginx/sites-available/default
sudo rm -f /etc/nginx/sites-enabled/default

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

echo "🔁 Testing and reloading Nginx..."
if nginx -t; then
    if [[ "$OS" == "mac" ]]; then
        brew services restart nginx
    else
        systemctl reload nginx
    fi
else
    echo "❌ Nginx configuration test failed."
    exit 1
fi

echo "✅ Nginx reverse proxy with SSL setup complete."
echo "🎉 All done!"