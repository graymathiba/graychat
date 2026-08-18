#!/bin/bash
# GryChat Production Deployment Script
# For Oracle Cloud Free Tier (Ubuntu 24.04 ARM)
# Run this on your server after cloning the repo

set -e

echo "=== GryChat Production Deployment ==="

# 1. Update system
echo "[1/8] Updating system..."
sudo apt-get update -qq && sudo apt-get upgrade -y -qq

# 2. Install Docker
echo "[2/8] Installing Docker..."
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker $USER
  echo "Docker installed. You may need to log out and back in for group changes."
fi

# 3. Install Docker Compose
echo "[3/8] Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
  sudo apt-get install -y docker-compose-plugin
fi

# 4. Configure UFW firewall
echo "[4/8] Configuring firewall..."
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw --force enable

# 5. Create certbot directory
echo "[5/8] Setting up certbot..."
mkdir -p certbot/conf certbot/www

# 6. Build and start services (nginx + backend only first, for cert generation)
echo "[6/8] Building containers..."
docker compose build backend

# 7. Start nginx to handle certbot challenge
echo "[7/8] Starting nginx for certificate generation..."
# Temporarily start nginx with HTTP-only config for cert verification
cat > nginx-temp.conf << 'EOF'
server {
    listen 80;
    server_name api.grychat.com;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        return 200 'ok';
    }
}
EOF

docker run -d --name nginx-temp \
  -p 80:80 \
  -v $(pwd)/nginx-temp.conf:/etc/nginx/conf.d/default.conf:ro \
  -v $(pwd)/certbot/www:/var/www/certbot:ro \
  nginx:alpine

echo ""
echo "=== NEXT STEPS ==="
echo ""
echo "1. Make sure DNS is set up: api.grychat.com → $(curl -s ifconfig.me)"
echo "   Check with: nslookup api.grychat.com"
echo ""
echo "2. Generate TLS certificate:"
echo "   docker run --rm -v $(pwd)/certbot/conf:/etc/letsencrypt \\"
echo "     -v $(pwd)/certbot/www:/var/www/certbot \\"
echo "     certbot/certbot certonly --webroot \\"
echo "     --webroot-path=/var/www/certbot \\"
echo "     -d api.grychat.com --email your@email.com --agree-tos --no-eff-email"
echo ""
echo "3. Remove temp nginx and start full stack:"
echo "   docker stop nginx-temp && docker rm nginx-temp"
echo "   rm nginx-temp.conf"
echo "   docker compose up -d"
echo ""
echo "4. Verify:"
echo "   curl https://api.grychat.com/health"
echo ""
echo "Done!"
