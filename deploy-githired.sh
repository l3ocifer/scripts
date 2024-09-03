#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Modify the cleanup function
cleanup() {
    log "An error occurred. Cleaning up..."
    if [ -f ~/traefik/docker-compose.yml ]; then
        cd ~/traefik && docker-compose down -v || log "Error stopping Traefik services"
    fi
    if [ -f ~/app/docker-compose.yml ]; then
        cd ~/app && docker-compose down -v || log "Error stopping app services"
    fi
    rm -rf ~/traefik ~/app
    log "Cleanup completed. Please check the logs and try again."
    exit 1
}

# Add this function for verbose Docker info
check_docker_info() {
    log "Checking Docker info..."
    docker info || log "Error getting Docker info"
    docker-compose version || log "Error getting Docker Compose version"
}

# Set trap for cleanup
trap cleanup ERR

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required commands
for cmd in docker docker-compose aws git; do
    if ! command_exists $cmd; then
        log "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

# Check AWS CLI configuration
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log "Error: AWS CLI is not configured correctly. Please run 'aws configure' and try again."
    exit 1
fi

log "Starting setup..."

# Create necessary directories
mkdir -p ~/traefik ~/app

# Clone the private GitHired repository
log "Cloning GitHired repository..."
git clone -b template-update git@github.com:GitHired-co/githired.git ~/app

# Configure .env file
log "Configuring environment variables..."
if [ -f ~/app/.env.example ]; then
    cp ~/app/.env.example ~/app/.env || { log "Error copying .env.example"; exit 1; }
else
    log "Warning: .env.example not found. Creating a basic .env file."
    cat > ~/app/.env << EOL
DOMAIN=githired.co
SECRET_KEY=$(openssl rand -hex 32)
FIRST_SUPERUSER=admin@githired.co
FIRST_SUPERUSER_PASSWORD=$(openssl rand -base64 12)
POSTGRES_PASSWORD=$(openssl rand -base64 12)
BACKEND_CORS_ORIGINS=["https://githired.co"]
EOL
fi

# Now, regardless of whether we copied .env.example or created a new .env, we can modify it
sed -i "s/DOMAIN=.*/DOMAIN=githired.co/" ~/app/.env
sed -i "s/SECRET_KEY=.*/SECRET_KEY=$(openssl rand -hex 32)/" ~/app/.env
sed -i "s/FIRST_SUPERUSER=.*/FIRST_SUPERUSER=admin@githired.co/" ~/app/.env
sed -i "s/FIRST_SUPERUSER_PASSWORD=.*/FIRST_SUPERUSER_PASSWORD=$(openssl rand -base64 12)/" ~/app/.env
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -base64 12)/" ~/app/.env
sed -i "s/BACKEND_CORS_ORIGINS=.*/BACKEND_CORS_ORIGINS=[\"https:\/\/githired.co\"]/" ~/app/.env
# Set up Traefik configuration
log "Setting up Traefik..."
cat > ~/traefik/traefik.toml << EOL
[entryPoints]
  [entryPoints.web]
    address = ":80"
    [entryPoints.web.http.redirections.entryPoint]
      to = "websecure"
      scheme = "https"
  [entryPoints.websecure]
    address = ":443"

[certificatesResolvers.letsencrypt.acme]
  email = "leo@githired.co"
  storage = "acme.json"
  [certificatesResolvers.letsencrypt.acme.tlsChallenge]

[api]
  dashboard = true

[providers.docker]
  exposedByDefault = false
  network = "traefik-public"

[providers.file]
  filename = "traefik_dynamic.toml"
EOL

# Create Traefik dynamic configuration file
cat > ~/traefik/traefik_dynamic.toml << EOL
[http.middlewares.simpleAuth.basicAuth]
  users = ["admin:$(htpasswd -nb admin changeme | sed -e s/\\$/\\$\\$/g)"]

[http.routers.dashboard]
  rule = "Host(\`traefik.githired.co\`)"
  entrypoints = ["websecure"]
  middlewares = ["simpleAuth"]
  service = "api@internal"
  [http.routers.dashboard.tls]
    certResolver = "letsencrypt"
EOL

# Set permissions for the ACME file
touch ~/traefik/acme.json && chmod 600 ~/traefik/acme.json

# Create Docker network
log "Creating Docker network..."
docker network create traefik-public

# Set up docker-compose for Traefik
cat > ~/traefik/docker-compose.yml << EOL
version: "3.7"

services:
  traefik:
    image: traefik:v2.9
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.toml:/traefik.toml:ro
      - ./traefik_dynamic.toml:/traefik_dynamic.toml:ro
      - ./acme.json:/acme.json
    networks:
      - traefik-public
    restart: always
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(\`traefik.githired.co\`)"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"

networks:
  traefik-public:
    external: true
EOL

# Modify FastAPI docker-compose.yml
log "Configuring FastAPI docker-compose.yml..."
sed -i 's/- "80:80"//' ~/app/docker-compose.yml
sed -i 's/- "8080:8080"//' ~/app/docker-compose.yml
sed -i '/^services:/a\  traefik:\n    external: true\n    name: traefik-public' ~/app/docker-compose.yml
sed -i 's/networks:/networks:\n  traefik:\n    external: true/' ~/app/docker-compose.yml
sed -i '/backend:/a\    networks:\n      - traefik\n    labels:\n      - "traefik.enable=true"\n      - "traefik.http.routers.backend.rule=Host(`githired.co`) && PathPrefix(`/api`, `/docs`, `/redoc`)"\n      - "traefik.http.routers.backend.entrypoints=websecure"\n      - "traefik.http.routers.backend.tls.certresolver=letsencrypt"' ~/app/docker-compose.yml
sed -i '/frontend:/a\    networks:\n      - traefik\n    labels:\n      - "traefik.enable=true"\n      - "traefik.http.routers.frontend.rule=Host(`githired.co`)"\n      - "traefik.http.routers.frontend.entrypoints=websecure"\n      - "traefik.http.routers.frontend.tls.certresolver=letsencrypt"' ~/app/docker-compose.yml
sed -i '/db:/a\    volumes:\n      - postgres_data:/var/lib/postgresql/data' ~/app/docker-compose.yml
sed -i '/^volumes:/a\  postgres_data:' ~/app/docker-compose.yml

# Set up ddclient for AWS Route 53
log "Configuring ddclient for AWS Route 53..."
cat > /tmp/ddclient.conf << EOL
daemon=300
ssl=yes
use=web, web=checkip.amazonaws.com
protocol=route53
server=route53.amazonaws.com
login=\`aws configure get aws_access_key_id\`
password=\`aws configure get aws_secret_access_key\`
zone=githired.co
githired.co
www.githired.co
EOL
sudo mv /tmp/ddclient.conf /etc/ddclient.conf
sudo systemctl restart ddclient
sudo systemctl enable ddclient

# Create startup service
log "Creating startup service..."
cat > /tmp/githired.service << EOL
[Unit]
Description=Start Githired Web Server
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/docker-compose -f /home/$USER/traefik/docker-compose.yml up -d
ExecStart=/usr/bin/docker-compose -f /home/$USER/app/docker-compose.yml up -d
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL
sudo mv /tmp/githired.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable githired.service

# Create container health check script
log "Creating health check script..."
cat > /tmp/check-containers.sh << EOL
#!/bin/bash

containers=("traefik_traefik_1" "app_backend_1" "app_frontend_1")

for container in "\${containers[@]}"; do
  if ! docker ps -q --filter "name=\$container" | grep -q .; then
    echo "Container \$container is not running. Restarting..."
    docker start \$container
  fi
done
EOL
sudo mv /tmp/check-containers.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/check-containers.sh

# Add cron job for health checks
log "Adding health check cron job..."
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/check-containers.sh") | crontab -

# Start services
log "Starting services..."
check_docker_info

if [ -f ~/traefik/docker-compose.yml ]; then
    cd ~/traefik && docker-compose up -d || log "Error starting Traefik services"
else
    log "Error: ~/traefik/docker-compose.yml not found. Skipping Traefik startup."
fi

if [ -f ~/app/docker-compose.yml ]; then
    cd ~/app && docker-compose up -d || log "Error starting app services"
else
    log "Error: ~/app/docker-compose.yml not found. Skipping app startup."
fi

# Initialize the database
log "Initializing the database..."
if [ -f ~/app/docker-compose.yml ]; then
    docker-compose exec -T backend alembic upgrade head
    docker-compose exec -T backend python /app/app/initial_data.py
else
    log "Error: ~/app/docker-compose.yml not found. Skipping database initialization."
fi
log "Setup complete. Please update AWS Route 53 settings and configure your router to forward ports 80 and 443."
