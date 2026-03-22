#!/bin/bash

# ===========================================
# New WordPress + Sage Project Setup Script
# ===========================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# -------------------------------------------
# Input
# -------------------------------------------
read -p "Project name (e.g. my-client): " PROJECT_NAME
read -p "Site title: " SITE_TITLE
read -p "Admin email: " ADMIN_EMAIL
read -p "Database password: " DB_PASS
read -p "GitHub theme repo (SSH, leave empty to skip): " THEME_REPO

# Derived variables
DB_NAME="${PROJECT_NAME//-/_}"
DB_USER="${DB_NAME}_user"
DOMAIN="${PROJECT_NAME}.local"
WP_PATH="/var/www/${PROJECT_NAME}"
THEME_NAME="${PROJECT_NAME}-theme"

echo ""
warning "Creating project: ${PROJECT_NAME}"
warning "Domain: http://${DOMAIN}"
warning "Database: ${DB_NAME}"
echo ""

# -------------------------------------------
# Database
# -------------------------------------------
log "Creating database..."
sudo mariadb -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
sudo mariadb -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
sudo mariadb -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mariadb -e "FLUSH PRIVILEGES;"

# -------------------------------------------
# Project folder
# -------------------------------------------
log "Creating project folder..."
sudo mkdir -p ${WP_PATH}
sudo chown -R ${USER}:${USER} ${WP_PATH}

# -------------------------------------------
# Virtual Host
# -------------------------------------------
log "Creating virtual host..."
sudo bash -c "cat > /etc/apache2/sites-available/${PROJECT_NAME}.conf <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    DocumentRoot ${WP_PATH}

    <Directory ${WP_PATH}>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF"

sudo a2ensite ${PROJECT_NAME}.conf
sudo systemctl reload apache2

# -------------------------------------------
# DNS local
# -------------------------------------------
log "Adding local DNS..."
if ! grep -q "${DOMAIN}" /etc/hosts; then
    echo "127.0.0.1       ${DOMAIN}" | sudo tee -a /etc/hosts > /dev/null
else
    warning "DNS entry already exists, skipping..."
fi

# -------------------------------------------
# WordPress
# -------------------------------------------
log "Downloading WordPress..."
wp core download --path=${WP_PATH} --locale=pt_BR

log "Creating wp-config.php..."
wp config create \
    --path=${WP_PATH} \
    --dbname=${DB_NAME} \
    --dbuser=${DB_USER} \
    --dbpass=${DB_PASS} \
    --dbhost=localhost

log "Installing WordPress..."
wp core install \
    --path=${WP_PATH} \
    --url=http://${DOMAIN} \
    --title="${SITE_TITLE}" \
    --admin_user=admin \
    --admin_password=admin123 \
    --admin_email=${ADMIN_EMAIL}

# -------------------------------------------
# .htaccess
# -------------------------------------------
log "Creating .htaccess..."
cat > ${WP_PATH}/.htaccess <<EOF
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
EOF

# -------------------------------------------
# Permalinks
# -------------------------------------------
log "Setting permalinks..."
wp rewrite structure '/%postname%/' --path=${WP_PATH}

# -------------------------------------------
# Uploads permissions
# -------------------------------------------
log "Setting uploads permissions..."
sudo mkdir -p ${WP_PATH}/wp-content/uploads
sudo chown -R www-data:www-data ${WP_PATH}/wp-content/uploads
sudo chmod -R 775 ${WP_PATH}/wp-content/uploads

# -------------------------------------------
# Theme
# -------------------------------------------
if [ -n "$THEME_REPO" ]; then
    log "Cloning theme..."
    git clone ${THEME_REPO} ${WP_PATH}/wp-content/themes/${THEME_NAME}

    log "Installing PHP dependencies..."
    cd ${WP_PATH}/wp-content/themes/${THEME_NAME}
    composer install

    log "Installing JS dependencies..."
    npm install

    log "Setting cache permissions..."
    sudo mkdir -p ${WP_PATH}/wp-content/cache
    sudo chown -R ${USER}:www-data ${WP_PATH}/wp-content/cache
    sudo chmod -R 775 ${WP_PATH}/wp-content/cache

    log "Activating theme..."
    wp theme activate ${THEME_NAME} --path=${WP_PATH}

    log "Optimizing Acorn..."
    wp acorn optimize --path=${WP_PATH}
else
    warning "No theme repo provided, skipping theme setup..."
fi

# -------------------------------------------
# Done
# -------------------------------------------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Project ready!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "  URL:      http://${DOMAIN}"
echo -e "  Admin:    http://${DOMAIN}/wp-admin"
echo -e "  User:     admin"
echo -e "  Password: admin123"
echo -e "  DB:       ${DB_NAME}"
echo ""
echo -e "${YELLOW}  Don't forget to run: npm run dev${NC}"
echo ""
