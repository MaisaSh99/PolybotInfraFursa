#!/bin/bash
set -e

REPO_PATH=$1
echo "📦 Deploying Nginx Production Config from $REPO_PATH"

echo "🧰 Installing prerequisites..."
sudo apt update
sudo apt install curl gnupg2 ca-certificates lsb-release ubuntu-keyring -y

echo "🔑 Adding official Nginx GPG key..."
curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

echo "📦 Setting up official Nginx repository..."
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" \
    | sudo tee /etc/apt/sources.list.d/nginx.list

echo "📌 Setting Nginx pinning priority..."
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
    | sudo tee /etc/apt/preferences.d/99nginx

echo "🔄 Updating apt and installing Nginx..."
sudo apt update
sudo apt install nginx -y

echo "🔐 Creating SSL directory and self-signed certificate..."
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/polybot.key \
    -out /etc/nginx/ssl/polybot.crt \
    -subj "/C=US/ST=NA/L=NA/O=Fursa/OU=Polybot/CN=maisaprod.fursa.click"

echo "⚙️ Copying Nginx config..."
sudo cp "$REPO_PATH/nginx-config/default.conf" /etc/nginx/conf.d/default.conf

echo "✅ Reloading Nginx..."
sudo systemctl enable nginx
sudo systemctl restart nginx

echo "🎉 Production Nginx setup complete!"
