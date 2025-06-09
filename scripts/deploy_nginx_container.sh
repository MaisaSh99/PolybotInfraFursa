#!/bin/bash

set -e

echo "🔄 Stopping and removing existing Nginx container if it exists..."
sudo docker stop mynginx || true
sudo docker rm mynginx || true

echo "📁 Ensuring config and cert directories exist..."
sudo mkdir -p /home/ubuntu/conf.d
sudo mkdir -p /home/ubuntu/certs

echo "🐳 Running new Nginx container..."
sudo docker run -d --name mynginx \
  -p 443:443 \
  -v /home/ubuntu/conf.d:/etc/nginx/conf.d/ \
  -v /home/ubuntu/certs:/etc/nginx/certs/ \
  nginx

echo "✅ Nginx container is up and running!"
