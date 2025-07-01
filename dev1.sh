#!/bin/sh

#V3
#CONTAINER_NAME="gdsv2"
CONTAINER_NAME="$(basename "$0" .sh)"

# If the container is running, attach to shell instead of rebuilding
if docker ps -q -f name="^/${CONTAINER_NAME}$" | grep -q .; then
  echo "Container '${CONTAINER_NAME}' is already running."
  echo "Attaching to interactive shell..."
  docker exec -it "$CONTAINER_NAME" bash
  exit 0
fi

# Get directory of script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_DIR="$SCRIPT_DIR/$CONTAINER_NAME"

# Create working directory
mkdir -p "$CONTAINER_DIR"

# Create directories for sharing
mkdir -p "$CONTAINER_DIR/root"
mkdir -p "$CONTAINER_DIR/html"

# Create simple index.html
cat > "$CONTAINER_DIR/html/index.html" <<EOF
<h1>index.html</h1>
EOF

# Create simple index.php
cat > "$CONTAINER_DIR/html/index.php" <<EOF
<?php
echo "<h1>index.php</h1>";
?>
EOF

# Create updated Dockerfile
cat > "$CONTAINER_DIR/Dockerfile" <<EOF
FROM debian:bookworm-slim

# Prevent prompts during install
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get upgrade -y && \\
    apt-get install -y --no-install-recommends \\
    nano curl wget htop nginx php php-fpm php-cli php-curl php-mbstring php-xml \\
    nodejs npm bash && \\
    rm -rf /var/lib/apt/lists/* && \\
    curl -fsSL https://code-server.dev/install.sh | sh && \\
    curl -LO https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \\
    chmod +x ttyd.x86_64 && \\
    mv ttyd.x86_64 /usr/local/bin/ttyd

# Setup Nginx with PHP-FPM
RUN mkdir -p /run/php && \\
    printf 'server {\\n\
    listen 80 default_server;\\n\
    listen [::]:80 default_server;\\n\
    root /var/www/html;\\n\
    index index.php index.html index.htm;\\n\
    server_name _;\\n\
    location / {\\n\
        try_files \$uri \$uri/ =404;\\n\
    }\\n\
    location ~ \\\\.php\$ {\\n\
        include snippets/fastcgi-php.conf;\\n\
        fastcgi_pass unix:/run/php/php-fpm.sock;\\n\
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;\\n\
    }\\n\
    location ~ /\\\\.ht {\\n\
        deny all;\\n\
    }\\n\
}\\n' > /etc/nginx/sites-available/default && \\
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

RUN echo '#!/bin/sh' > /start.sh && \\
    echo 'mkdir -p /run/php' >> /start.sh && \\
    echo 'if [ ! -f /usr/local/bin/php-fpm ]; then ln -s /usr/sbin/php-fpm8.2 /usr/local/bin/php-fpm; fi' >> /start.sh && \\
    echo 'ln -sf /run/php/php8.2-fpm.sock /run/php/php-fpm.sock' >> /start.sh && \\
    echo 'php-fpm' >> /start.sh && \\
    echo 'ttyd --writable bash &' >> /start.sh && \\
    echo 'code-server --bind-addr 0.0.0.0:8082 --auth none &' >> /start.sh && \\
    echo 'exec nginx -g "daemon off;"' >> /start.sh && \\
    chmod +x /start.sh

EXPOSE 80 3000 8082
CMD ["/start.sh"]
EOF

# Build the Docker image
docker build -t "$CONTAINER_NAME" "$CONTAINER_DIR"

# Remove old container if it exists (but not running)
docker rm -f "$CONTAINER_NAME" 2>/dev/null

# Run the container with volume and port forwarding
docker run -d --restart=unless-stopped --name "$CONTAINER_NAME" \
  --hostname "$CONTAINER_NAME" \
  -v "$CONTAINER_DIR":/srv \
  -v "$CONTAINER_DIR/root":/root \
  -v "$CONTAINER_DIR/html":/var/www/html \
  -v /root/deb-cache:/var/cache/apt/archives \
  -p 8080:80 \
  -p 3000:3000 \
  -p 8081:7681 \
  -p 8082:8082 \
  -it "$CONTAINER_NAME"

# Print access info
echo ""
echo "Container '$CONTAINER_NAME' started."
echo "Services:"
echo "  - Nginx with PHP: http://localhost:8080"
echo "  - Node.js apps: http://localhost:3000"
echo "  - #SHELL -->  docker exec -it $CONTAINER_NAME bash"
