#!/bin/bash
set -euo pipefail

# Barvy
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${GREEN}[OK]${NC} $1"; }
info()    { echo -e "${BLUE}[..]${NC} $1"; }
error()   { echo -e "${RED}[!!]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && error "Spusť jako root: sudo bash install-n8n.sh"

# KONFIGURACE

echo ""
echo "n8n instalace"
echo ""

echo "Přístup:"
echo "  1) Veřejná doména (HTTPS / Let's Encrypt)"
echo "  2) IP adresa / VPN (HTTP)"
echo ""
read -rp "Volba [1/2]: " ACCESS_TYPE

if [[ "$ACCESS_TYPE" == "1" ]]; then
  read -rp "Doména (např. n8n.firma.cz): " N8N_HOST
  [[ -z "$N8N_HOST" ]] && error "Doména nesmí být prázdná."
  read -rp "E-mail pro Let's Encrypt: " LETSENCRYPT_EMAIL
  [[ -z "$LETSENCRYPT_EMAIL" ]] && error "E-mail nesmí být prázdný."
  USE_DOMAIN=true
elif [[ "$ACCESS_TYPE" == "2" ]]; then
  DETECTED_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
  read -rp "IP adresa serveru [$DETECTED_IP]: " N8N_HOST_INPUT
  N8N_HOST="${N8N_HOST_INPUT:-$DETECTED_IP}"
  USE_DOMAIN=false
else
  error "Neplatná volba."
fi

echo ""
read -rp "Název databáze [n8n]: " DB_NAME
DB_NAME="${DB_NAME:-n8n}"
read -rp "Uživatel databáze [n8n]: " DB_USER
DB_USER="${DB_USER:-n8n}"

echo "Heslo k databázi [Enter = vygenerovat automaticky]: "
read -rsp "Heslo: " DB_PASS_INPUT || true
echo ""
DB_PASS_INPUT="${DB_PASS_INPUT:-}"
if [[ -z "$DB_PASS_INPUT" ]]; then
  DB_PASS=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
  info "Heslo vygenerováno automaticky."
else
  DB_PASS="$DB_PASS_INPUT"
fi

N8N_ENCRYPTION_KEY=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)

echo ""
if [[ "$USE_DOMAIN" == true ]]; then
  echo "  Přístup:    https://$N8N_HOST"
else
  echo "  Přístup:    http://$N8N_HOST"
fi
echo "  Databáze:   PostgreSQL / $DB_NAME"
echo ""
read -rp "Pokračovat? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && { info "Zrušeno."; exit 0; }

# 1. ZÁVISLOSTI
info "Instalace závislostí..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q curl ca-certificates ufw nginx

if [[ "$USE_DOMAIN" == true ]]; then
  apt-get install -y -q certbot python3-certbot-nginx
fi

log "Závislosti nainstalovány."

# 2. POSTGRESQL
info "Instalace PostgreSQL..."

apt-get install -y -q postgresql postgresql-contrib
systemctl enable --now postgresql

sudo -u postgres psql <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE "${DB_USER}" WITH LOGIN PASSWORD '${DB_PASS}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE "${DB_NAME}" OWNER "${DB_USER}"'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')
\gexec
EOF

log "PostgreSQL připraven."

# 3. NODE.JS 20 LTS
info "Instalace Node.js 20 LTS..."

curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
apt-get install -y -q nodejs

log "Node.js $(node --version) nainstalován."

# 4. N8N
info "Instalace n8n..."

if ! id "n8n" &>/dev/null; then
  useradd --system --shell /usr/sbin/nologin --create-home --home-dir /opt/n8n n8n
fi

npm install -g n8n
mkdir -p /opt/n8n/.n8n
chown -R n8n:n8n /opt/n8n

log "n8n nainstalován."

# 5. KONFIGURACE
info "Vytváření konfigurace..."

mkdir -p /etc/n8n
chmod 750 /etc/n8n

if [[ "$USE_DOMAIN" == true ]]; then
  WEBHOOK_URL="https://${N8N_HOST}/"
  N8N_PROTOCOL="https"
  SECURE_COOKIE="true"
else
  WEBHOOK_URL="http://${N8N_HOST}/"
  N8N_PROTOCOL="http"
  SECURE_COOKIE="false"
fi

cat > /etc/n8n/n8n.env <<EOF
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=localhost
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=${DB_NAME}
DB_POSTGRESDB_USER=${DB_USER}
DB_POSTGRESDB_PASSWORD=${DB_PASS}

N8N_HOST=${N8N_HOST}
N8N_PORT=5678
N8N_PROTOCOL=${N8N_PROTOCOL}
WEBHOOK_URL=${WEBHOOK_URL}

N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_SECURE_COOKIE=${SECURE_COOKIE}

N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console
N8N_USER_FOLDER=/opt/n8n/.n8n
N8N_DIAGNOSTICS_ENABLED=false
EOF

chmod 600 /etc/n8n/n8n.env
chown root:root /etc/n8n/n8n.env

log "Konfigurace uložena do /etc/n8n/n8n.env"

# 6. SYSTEMD
info "Vytváření systemd service..."

cat > /etc/systemd/system/n8n.service <<EOF
[Unit]
Description=n8n
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=n8n
Group=n8n
EnvironmentFile=/etc/n8n/n8n.env
WorkingDirectory=/opt/n8n
ExecStart=$(which n8n) start
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/n8n/.n8n
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable n8n
log "systemd service vytvořena."

# 7. NGINX
info "Konfigurace Nginx..."

cat > /etc/nginx/sites-available/n8n <<EOF
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

server {
    listen 80;
    server_name ${N8N_HOST};

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
    }
}
EOF

ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl enable --now nginx
log "Nginx nakonfigurován."

# 8. FIREWALL
info "Konfigurace firewallu..."

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp

if [[ "$USE_DOMAIN" == true ]]; then
  ufw allow 443/tcp
fi

ufw --force enable
log "Firewall aktivován (SSH + HTTP$([ "$USE_DOMAIN" == true ] && echo '/HTTPS'), port 5678 blokován zvenčí)."

# 8. HTTPS (pouze doména)
if [[ "$USE_DOMAIN" == true ]]; then
  info "Získávám SSL certifikát..."
  certbot --nginx --non-interactive --agree-tos \
    --email "$LETSENCRYPT_EMAIL" \
    --domains "$N8N_HOST" \
    --redirect
  log "HTTPS certifikát nainstalován."
fi

# SPUŠTĚNÍ
info "Spouštím n8n..."
systemctl start n8n
sleep 4

if systemctl is-active --quiet n8n; then
  log "n8n běží."
else
  echo ""
  echo "n8n se nespustil. Logy:"
  journalctl -u n8n -n 20 --no-pager
  exit 1
fi

# VÝSLEDEK
echo ""
echo "Instalace dokončena."
echo ""
if [[ "$USE_DOMAIN" == true ]]; then
  echo "  URL:             https://${N8N_HOST}"
else
  echo "  URL:             http://${N8N_HOST}"
fi
echo ""
echo "  Logy:            journalctl -u n8n -f"
echo "  Restart:         systemctl restart n8n"
echo "  Aktualizace:     npm update -g n8n"
echo ""
echo "  Konfig:          /etc/n8n/n8n.env  (root only)"
echo "  DB heslo:        ${DB_PASS}"
echo "  Encryption key:  ${N8N_ENCRYPTION_KEY}"
echo ""
echo "  POZOR: Uloz encryption key na bezpecne misto."
echo "         Bez ni nelze obnovit credentials v n8n."
echo ""