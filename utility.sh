#!/bin/bash
set -e

# OS Detection
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

# Reusable package install function
install_package() {
    local name=$1
    local check_cmd=$2
    local install_cmd=$3

    echo -n "🔍 Checking for $name... "
    if eval "$check_cmd" &>/dev/null; then
        echo "✅ Already installed."
    else
        echo "📦 Installing $name..."
        eval "$install_cmd"
    fi
}

# macOS
if [ "$OS" == "mac" ]; then
    if ! command -v brew &>/dev/null; then
        echo "🍺 Installing Homebrew..."
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
    fi
fi

# OS-specific install logic
case "$OS" in
  debian)
    sudo apt-get update -y

    install_package "Docker" "command -v docker" "sudo apt-get install -y docker.io"

    install_package "Jenkins" "command -v jenkins" "
      sudo rm -f /etc/apt/sources.list.d/jenkins.list /usr/share/keyrings/jenkins-keyring.gpg &&
      curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | gpg --dearmor | sudo tee /usr/share/keyrings/jenkins-keyring.gpg > /dev/null &&
      echo 'deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/' | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null &&
      sudo apt-get update -y &&
      sudo apt-get install -y openjdk-17-jdk jenkins
    "

    install_package "Maven" "command -v mvn" "sudo apt-get install -y maven"
    install_package "Nginx" "command -v nginx" "sudo apt-get install -y nginx"
    ;;

  rhel)
    sudo yum install -y epel-release
    sudo yum update -y

    install_package "Docker" "command -v docker" "sudo yum install -y docker && sudo systemctl enable --now docker"

    install_package "Jenkins" "command -v jenkins" "
      sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo &&
      sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key &&
      sudo yum install -y java-17-openjdk jenkins
    "

    install_package "Maven" "command -v mvn" "sudo yum install -y maven"
    install_package "Nginx" "command -v nginx" "sudo yum install -y nginx"
    ;;

  mac)
    install_package "Docker" "command -v docker" "brew install --cask docker"
    install_package "Jenkins" "command -v jenkins-lts" "brew install jenkins-lts"
    install_package "Maven" "command -v mvn" "brew install maven"
    install_package "Nginx" "command -v nginx" "brew install nginx"
    ;;
esac

echo "✅ All required software is installed."