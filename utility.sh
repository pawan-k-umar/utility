#!/bin/bash
set -e

# Detect OS
OS=""
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="mac"
else
    echo "❌ Unsupported OS: $OSTYPE"
    exit 1
fi

echo "🖥️ Detected OS: $OS"

# Function to install software if not present
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
    fi
}

# Homebrew setup for macOS
if [ "$OS" == "mac" ] && ! command -v brew &>/dev/null; then
    echo "🍺 Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
fi

# Install software based on OS
case "$OS" in
  debian)
    sudo su -c "
      apt-get update -y

      # Docker
      if ! command -v docker &>/dev/null; then
        apt-get install -y docker.io
        systemctl enable --now docker
      fi

      # Jenkins (with proper key workaround)
      if ! command -v jenkins &>/dev/null; then
        apt-get install -y curl gnupg2 openjdk-17-jdk
        curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg
        echo 'deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/' > /etc/apt/sources.list.d/jenkins.list
        apt-get update -y
        apt-get install -y jenkins
        systemctl enable --now jenkins
      fi

      # Maven
      if ! command -v mvn &>/dev/null; then
        apt-get install -y maven
      fi

      # Nginx
      if ! command -v nginx &>/dev/null; then
        apt-get install -y nginx
        systemctl enable --now nginx
      fi
    "
    ;;

  rhel)
    sudo su -c "
      yum install -y epel-release
      yum update -y

      if ! command -v docker &>/dev/null; then
        yum install -y docker
        systemctl enable --now docker
      fi

      if ! command -v jenkins &>/dev/null; then
        wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
        rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
        yum install -y java-17-openjdk jenkins
        systemctl enable --now jenkins
      fi

      if ! command -v mvn &>/dev/null; then
        yum install -y maven
      fi

      if ! command -v nginx &>/dev/null; then
        yum install -y nginx
        systemctl enable --now nginx
      fi
    "
    ;;

  mac)
    install_package "Docker" "command -v docker" "brew install --cask docker"
    install_package "Jenkins" "command -v jenkins-lts" "brew install jenkins-lts"
    install_package "Maven" "command -v mvn" "brew install maven"
    install_package "Nginx" "command -v nginx" "brew install nginx"
    ;;
esac

echo "✅ All required software is installed."