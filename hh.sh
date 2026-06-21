#!/bin/bash
# =============================================================================
# n8n Instalační skript
# Ubuntu 22.04 / 24.04 | Node.js 20 LTS | PostgreSQL | Nginx | Certbot | ufw
# Spusť jako root nebo pomocí sudo: sudo bash install-n8n.sh
# =============================================================================

set -euo pipefail

# ── Barvy pro výstup ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()     { echo -e "${GREEN}[✓]${NC} $1"; }
info()    { echo -e "${BLUE}[i]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
error "Skript musí být spuštěn jako root. Použij: sudo bash install-n8n.sh"
fi

# =============================================================================
# INTERAKTIVNÍ KONFIGURACE
# =============================================================================
section "Konfigurace instalace"

echo ""
echo "Tento skript nainstaluje n8n s PostgreSQL, Nginx a Certbot na Ubuntu."
echo ""

# ── Typ přístupu: IP nebo doména ──────────────────────────────────────────────
echo "Jak bude n8n přístupné?"
echo "  1) Veřejná doména (+ automatické HTTPS přes Let's Encrypt)"
echo "  2) IP adresa (pouze HTTP nebo self-signed HTTPS)"
echo ""
read -rp "Volba [1/2]: " ACCESS_TYPE

if [[ "$ACCESS_TYPE" == "1" ]]; then
read -rp "Zadej doménu (např. n8n.mojedomena.cz): " N8N_DOMAIN
[[ -z "$N8N_DOMAIN" ]] && error "Doména nesmí být prázdná."
read -rp "E-mail pro Let's Encrypt certifikát: " LETSENCRYPT_EMAIL
[[ -z "$LETSENCRYPT_EMAIL" ]] && error "E-mail nesmí být prázdný."
N8N_HOST="$N8N_DOMAIN"
USE_DOMAIN=true
elif [[ "$ACCESS_TYPE" == "2" ]]; then
# Zjisti veřejnou IP automaticky
DETECTED_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
read -rp "Zadej IP adresu serveru [$DETECTED_IP]: " N8N_IP_INPUT
N8N_HOST="${N8N_IP_INPUT:-$DETECTED_IP}"
USE_DOMAIN=false
else
error "Neplatná volba."
fi

echo ""

# ── PostgreSQL credentials ────────────────────────────────────────────────────
info "Nastavení PostgreSQL pro n8n:"
read -rp "Název databáze [n8n]: " DB_NAME
DB_NAME="${DB_NAME:-n8n}"
read -rp "Uživatel databáze [n8n]: " DB_USER
DB_USER="${DB_USER:-n8n}"

# Generuj silné heslo nebo nech uživatele zadat
echo "Heslo k databázi: [Enter = automaticky vygenerovat silné heslo]"
read -rsp "Heslo: " DB_PASS_INPUT || true
echo ""
DB_PASS_INPUT="${DB_PASS_INPUT:-}"
if [[ -z "$DB_PASS_INPUT" ]]; then
DB_PASS=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
info "Vygenerováno silné heslo pro databázi."
else
DB_PASS="$DB_PASS_INPUT"
fi

echo ""

# ── N8N_ENCRYPTION_KEY ────────────────────────────────────────────────────────
info "Generuji N8N_ENCRYPTION_KEY (šifrování credentials v n8n)..."
N8N_ENCRYPTION_KEY=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)

echo ""

# ── Shrnutí před instalací ────────────────────────────────────────────────────
section "Shrnutí konfigurace"
if [[ "$USE_DOMAIN" == true ]]; then
echo "  Přístup:          https://$N8N_HOST (HTTPS via Let's Encrypt)"
else
echo "  Přístup:          http://$N8N_HOST:80 (IP adresa, HTTP)"
fi
echo "  Databáze:         PostgreSQL ($DB_NAME @ localhost)"
echo "  DB uživatel:      $DB_USER"
echo "  Systémový user:   n8n (bez login shellu)"
echo "  Process manager:  systemd"
echo "  Reverse proxy:    Nginx"
echo ""
warn "Encryption key a DB heslo budou uloženy do /etc/n8n/n8n.env (přístup jen root)"
echo ""
read -rp "Pokračovat s instalací? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && { info "Instalace zrušena."; exit 0; }

# =============================================================================
# 1. SYSTÉMOVÁ PŘÍPRAVA
# =============================================================================
section "1/7 Aktualizace systému a instalace závislostí"

export DEBIAN_FRONTEND=noninteractive
apt update
apt upgrade -y
apt autoremove -y
apt autoclean
apt install -y \
curl wget ca-certificates lsb-release \
ufw nginx \
git build-essential

log "Systém aktualizován a závislosti nainstalovány."

# =============================================================================
# 2. POSTGRESQL
# =============================================================================
section "2/7 Instalace a konfigurace PostgreSQL"

apt-get install -y -q postgresql postgresql-contrib

systemctl enable --now postgresql
log "PostgreSQL nainstalován a spuštěn."

# Vytvoř DB uživatele a databázi
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

log "PostgreSQL databáze '$DB_NAME' a uživatel '$DB_USER' vytvořeny."

# =============================================================================
# 3. NODE.JS 20 LTS (přes NodeSource)
# =============================================================================
section "3/7 Instalace Node.js 20 LTS"

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y -q nodejs

NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
log "Node.js $NODE_VERSION a npm $NPM_VERSION nainstalovány."

# =============================================================================
# 4. N8N INSTALACE
# =============================================================================
section "4/7 Instalace n8n (globálně přes npm)"

# Dedikovaný systémový uživatel
if ! id "n8n" &>/dev/null; then
useradd --system --shell /usr/sbin/nologin --create-home --home-dir /opt/n8n n8n
log "Systémový uživatel 'n8n' vytvořen."
else
log "Uživatel 'n8n' již existuje."
fi

# Nainstaluj n8n globálně
npm install -g n8n
log "n8n nainstalován: $(n8n --version 2>/dev/null || echo 'OK')"

# Adresář pro data
mkdir -p /opt/n8n/.n8n
chown -R n8n:n8n /opt/n8n

# =============================================================================
# 5. KONFIGURACE PROSTŘEDÍ
# =============================================================================
section "5/7 Konfigurace n8n (environment variables)"

mkdir -p /etc/n8n
chmod 750 /etc/n8n

if [[ "$USE_DOMAIN" == true ]]; then
WEBHOOK_URL="https://${N8N_HOST}/"
N8N_PROTOCOL="https"
else
WEBHOOK_URL="http://${N8N_HOST}/"
N8N_PROTOCOL="http"
fi

cat > /etc/n8n/n8n.env <<EOF
# =============================================================================
# n8n Environment konfigurace
# Vygenerováno: $(date)
# POZOR: Tento soubor obsahuje citlivé údaje – přístup jen pro root!
# =============================================================================

# Databáze
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=localhost
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=${DB_NAME}
DB_POSTGRESDB_USER=${DB_USER}
DB_POSTGRESDB_PASSWORD=${DB_PASS}

# n8n základní nastavení
N8N_HOST=${N8N_HOST}
N8N_PORT=5678
N8N_PROTOCOL=${N8N_PROTOCOL}
WEBHOOK_URL=${WEBHOOK_URL}

# Bezpečnost
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

# Logování
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console

# Pracovní adresář
N8N_USER_FOLDER=/opt/n8n/.n8n

# Diagnostika (vypnutá telemetrie)
N8N_DIAGNOSTICS_ENABLED=false
N8N_VERSION_NOTIFICATIONS_ENABLED=true
EOF

chmod 600 /etc/n8n/n8n.env
chown root:root /etc/n8n/n8n.env
log "Konfigurační soubor /etc/n8n/n8n.env vytvořen (přístup: root only)."

# =============================================================================
# 6. SYSTEMD SERVICE
# =============================================================================
section "6/7 Vytvoření systemd service"

cat > /etc/systemd/system/n8n.service <<EOF
[Unit]
Description=n8n Workflow Automation
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
SyslogIdentifier=n8n

# Bezpečnostní omezení
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
log "systemd service 'n8n' vytvořena a povolena."

# =============================================================================
# 7. NGINX + FIREWALL
# =============================================================================
section "7/7 Nginx, Certbot a firewall (ufw)"

# ── Základní Nginx config ─────────────────────────────────────────────────────
cat > /etc/nginx/sites-available/n8n <<EOF
# n8n reverse proxy
# Vygenerováno: $(date)

map \$http_upgrade \$connection_upgrade {
default upgrade;
''      close;
}

server {
listen 80;
server_name ${N8N_HOST};

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
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
        proxy_connect_timeout 75s;
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
    }
}
EOF

# Aktivace site
ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl enable --now nginx
log "Nginx nakonfigurován."

# ── Firewall ──────────────────────────────────────────────────────────────────
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 'Nginx Full'   # porty 80 + 443
# Port 5678 NENÍ otevřen zvenčí – přístup jen přes Nginx
ufw --force enable
log "Firewall (ufw) nakonfigurován: SSH + HTTP/HTTPS povoleny, port 5678 blokován zvenčí."

# ── HTTPS (Certbot) pouze pro doménu ─────────────────────────────────────────
if [[ "$USE_DOMAIN" == true ]]; then
info "Získávám Let's Encrypt certifikát pro $N8N_HOST..."
certbot --nginx \
--non-interactive \
--agree-tos \
--email "$LETSENCRYPT_EMAIL" \
--domains "$N8N_HOST" \
--redirect
log "HTTPS certifikát nainstalován."

# Automatická obnova certifikátu
systemctl enable --now certbot.timer 2>/dev/null || \
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
log "Automatická obnova certifikátu nastavena."
else
warn "Používáš IP adresu – HTTPS není nakonfigurováno."
warn "Doporučujeme nasadit za VPN nebo přidat doménu pro plnou bezpečnost."
fi

# =============================================================================
# SPUŠTĚNÍ N8N
# =============================================================================
section "Spouštím n8n..."
systemctl start n8n
sleep 3

if systemctl is-active --quiet n8n; then
log "n8n běží!"
else
warn "n8n se nespustil správně. Zkontroluj logy: journalctl -u n8n -n 50"
fi

# =============================================================================
# VÝSLEDNÉ SHRNUTÍ
# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║             INSTALACE DOKONČENA ÚSPĚŠNĚ                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
if [[ "$USE_DOMAIN" == true ]]; then
echo -e "  🌐  n8n URL:        ${GREEN}https://${N8N_HOST}${NC}"
else
echo -e "  🌐  n8n URL:        ${YELLOW}http://${N8N_HOST}${NC}"
fi
echo ""
echo "  📋  Užitečné příkazy:"
echo "      systemctl status n8n          # stav služby"
echo "      systemctl restart n8n         # restart"
echo "      journalctl -u n8n -f          # živé logy"
echo "      npm update -g n8n             # aktualizace n8n"
echo ""
echo -e "  🔐  ${YELLOW}DŮLEŽITÉ – ulož na bezpečné místo:${NC}"
echo "      Konfig soubor:       /etc/n8n/n8n.env"
echo "      DB heslo:            $DB_PASS"
echo "      Encryption key:      $N8N_ENCRYPTION_KEY"
echo ""
echo -e "  ${RED}⚠  VAROVÁNÍ: Bez encryption key nelze obnovit uložené credentials v n8n!${NC}"
echo ""