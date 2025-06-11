#!/bin/bash

set -e

echo "🔍 Checking if Docker is installed..."
if ! command -v docker &> /dev/null; then
    echo "🐳 Docker not found. Installing Docker..."

    # Update package index
    sudo apt update

    # Install prerequisites
    sudo apt install apt-transport-https ca-certificates curl software-properties-common -y

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package index again
    sudo apt update

    # Install Docker
    sudo apt install docker-ce docker-ce-cli containerd.io -y

    # Start and enable Docker service
    sudo systemctl start docker
    sudo systemctl enable docker

    echo "✅ Docker installed successfully!"
else
    echo "✅ Docker is already installed"
fi

echo "🔄 Stopping and removing existing Nginx container if it exists..."
sudo docker stop mynginx || true
sudo docker rm mynginx || true

echo "📁 Ensuring config and cert directories exist..."
sudo mkdir -p /home/ubuntu/conf.d
sudo mkdir -p /home/ubuntu/certs

echo "🔐 Generating SSL certificates if they don't exist..."
if [ ! -f /home/ubuntu/certs/polybot.crt ] || [ ! -f /home/ubuntu/certs/polybot.key ]; then
    echo "📜 Creating self-signed SSL certificates..."
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /home/ubuntu/certs/polybot.key \
        -out /home/ubuntu/certs/polybot.crt \
        -subj "/C=US/ST=NA/L=NA/O=Fursa/OU=Polybot/CN=maisaprod.fursa.click"

    echo "🔑 Setting proper permissions for certificates..."
    sudo chmod 600 /home/ubuntu/certs/polybot.key
    sudo chmod 644 /home/ubuntu/certs/polybot.crt
else
    echo "✅ SSL certificates already exist, skipping generation..."
fi

echo "🐳 Running new Nginx container..."
sudo docker run -d --name mynginx \
  -p 443:443 \
  -v /home/ubuntu/conf.d:/etc/nginx/conf.d/ \
  -v /home/ubuntu/certs:/etc/nginx/certs/ \
  nginx

echo "⏳ Waiting for container to start..."
sleep 10

echo "🔍 Checking if Nginx container is running..."
if sudo docker ps | grep -q mynginx; then
    echo "✅ Nginx container is up and running!"
    echo "📊 Container status:"
    sudo docker ps | grep mynginx
else
    echo "❌ Nginx container failed to start. Checking logs..."
    sudo docker logs mynginx
    exit 1
fi

echo "🔍 Testing Nginx configuration..."
sudo docker exec mynginx nginx -t && echo "✅ Nginx config is valid" || echo "❌ Nginx config has errors"