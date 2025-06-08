#!/bin/bash
set -e

DOMAIN="kpawan.com"
JENKINS_SUB="jenkins.kpawan.com"
SPRING_PORT=9091
JENKINS_PORT=8080
EMAIL="pawan@gmail.com"

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

# Function to install package if missing
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

# Ensure user 'jenkins' exists (Linux only)
if [[ "$OS" == "debian" || "$OS" == "rhel" ]]; then
    if id -u jenkins &>/dev/null; then
        echo "👤 User 'jenkins' exists."
    else
        echo "👤 Creating user 'jenkins'..."
        sudo useradd -m -s /bin/bash jenkins
    fi
fi

# macOS homebrew install if missing
if [ "$OS" == "mac" ] && ! command -v brew &>/dev/null; then
    echo "🍺 Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
fi

case "$OS" in
  debian)
    echo "📦 Updating apt package index..."
    sudo apt-get update -y

    install_package "Docker" "command -v docker" "sudo apt-get install -y docker.io && sudo systemctl enable docker"
    install_package "curl" "command -v curl" "sudo apt-get install -y curl"
    install_package "gnupg2" "command -v gpg" "sudo apt-get install -y gnupg2"
    install_package "openjdk-17-jdk" "java -version" "sudo apt-get install -y openjdk-17-jdk"
    
    # Jenkins repo & install
    if ! command -v jenkins &>/dev/null; then
      echo "📦 Adding Jenkins repo and installing Jenkins..."
      curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list
      sudo apt-get update -y
      sudo apt-get install -y jenkins
      sudo systemctl enable jenkins
    else
      echo "✅ Jenkins already installed."
    fi

    install_package "Maven" "command -v mvn" "sudo apt-get install -y maven"
    install_package "Nginx" "command -v nginx" "sudo apt-get install -y nginx && sudo systemctl enable nginx"

    # Add jenkins to docker group
    echo "🔐 Adding Jenkins user to Docker group..."
    if id -nG jenkins | grep -qw docker; then
        echo "✅ Jenkins user is already in the Docker group."
    else
        sudo usermod -aG docker jenkins
        echo "🔁 Restarting Jenkins for group changes to take effect..."
        sudo systemctl restart jenkins
        echo "⚠️ Jenkins restarted — please re-run the script after this."
        exit 1
    fi
    ;;

  rhel)
    echo "📦 Enabling EPEL and updating system..."
    sudo yum install -y epel-release
    sudo yum update -y

    install_package "Docker" "command -v docker" "sudo yum install -y docker && sudo systemctl enable docker"
    
    # Jenkins repo & install
    if ! command -v jenkins &>/dev/null; then
      echo "📦 Adding Jenkins repo and installing Jenkins..."
      sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
      sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
      sudo yum install -y java-17-openjdk jenkins
      sudo systemctl enable jenkins
    else
      echo "✅ Jenkins already installed."
    fi

    install_package "Maven" "command -v mvn" "sudo yum install -y maven"
    install_package "Nginx" "command -v nginx" "sudo yum install -y nginx && sudo systemctl enable nginx"

    # Add jenkins to docker group
    echo "🔐 Adding Jenkins user to Docker group..."
    if id -nG jenkins | grep -qw docker; then
        echo "✅ Jenkins user is already in the Docker group."
    else
        sudo usermod -aG docker jenkins
        echo "🔁 Restarting Jenkins for group changes to take effect..."
        sudo systemctl restart jenkins
        echo "⚠️ Jenkins restarted — please re-run the script after this."
        exit 1
    fi
    ;;

  mac)
    install_package "Docker" "command -v docker" "brew install --cask docker"
    install_package "Jenkins LTS" "brew list | grep -qw jenkins-lts" "brew install jenkins-lts"
    install_package "Maven" "command -v mvn" "brew install maven"
    install_package "Nginx" "command -v nginx" "brew install nginx"

    echo "⚠️ On macOS, add Jenkins user to docker group is not applicable."
    echo "ℹ️ Please ensure Docker Desktop is running."

    echo "⚠️ To start Jenkins service on macOS, run: brew services start jenkins-lts"
    echo "⚠️ To start Nginx service on macOS, run: brew services start nginx"
    ;;
esac

# Start services depending on OS
echo "🚀 Starting Jenkins, Docker, and Nginx services..."

case "$OS" in
  debian|rhel)
    sudo systemctl start jenkins
    sudo systemctl start docker
    sudo systemctl start nginx
    ;;
  mac)
    echo "🚀 Starting Jenkins and Nginx services via brew..."
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

echo "✅ All required software installed and services started (or instructions provided)."