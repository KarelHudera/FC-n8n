#!/bin/bash
set -euo pipefail

RED='\033;31m'
GREEN='\033;32m'
BLUE='\033;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[OK]${NC} $1"; }
info()  { echo -e "${BLUE}[..]${NC} $1"; }
error() { echo -e "${RED}[!!]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && error "Spusť jako root: sudo bash install-n8n.sh"

DB_NAME="n8n"
DB_USER="n8n"

# Perzistentní kontrola šifrovacího klíče pro zamezení chyb mismatching keys
EXISTING_KEY=""
if [[ -f /etc/n8n/n8n.env ]]; then
  EXISTING_KEY=$(grep 'N8N_ENCRYPTION_KEY=' /etc/n8n/n8n.env | cut -d'=' -f2)
fi

if [[ -n "${N8N_HOST:-}" ]]; then
  info "Konfigurace převzata z prostředí."
else
  DETECTED_IP=$(hostname -I | awk '{print $1}')
  info "Spouštím konfigurační webserver na https://$DETECTED_IP ..."

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q
  apt-get install -y -q python3 ufw openssl

  openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
    -keyout /tmp/setup.key \
    -out /tmp/setup.crt \
    -subj "/CN=$DETECTED_IP" \
    -addext "subjectAltName=IP:$DETECTED_IP" 2>/dev/null

  ufw allow 443/tcp > /dev/null 2>&1 || true
  rm -f /tmp/n8n_config

  cat > /tmp/setup.html << HTML
<!DOCTYPE html>
<html lang="cs">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Instalace n8n</title>
<link href="https://cdn.jsdelivr.net/npm/@mdi/font@7.2.96/css/materialdesignicons.min.css" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root {
    --font-family-base: "Manrope", sans-serif;
    --body-bg: #f8f9fa;
    --card-bg: #ffffff;
    --border-color: #dadde6;
    --text-main: #505459;
    --text-heading: #17191C;
    --text-muted: #737880;
    --brand-primary: #069bfe;
    --brand-primary-hover: #058ae2;
    --border-radius: 8px;
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: var(--font-family-base);
    background-color: var(--body-bg);
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
    padding: 20px;
    color: var(--text-main);
    -webkit-font-smoothing: antialiased;
  }

  .card {
    background: var(--card-bg);
    border-radius: var(--border-radius);
    padding: 36px;
    max-width: 500px;
    width: 100%;
    border: 1px solid var(--border-color);
    box-shadow: 0px 2px 16px rgba(0, 0, 0, 0.03);
  }

  h1 {
    font-size: 24px;
    color: var(--text-heading);
    margin-bottom: 6px;
    font-weight: 500;
    letter-spacing: -0.3px;
  }

  .subtitle {
    color: var(--text-muted);
    font-size: 13.5px;
    margin-bottom: 28px;
    font-weight: 400;
  }

  .ip-box {
    background: #E5EEFF;
    border-radius: 6px;
    padding: 14px 18px;
    margin-bottom: 24px;
    font-size: 14px;
    color: #2368AD;
    font-weight: 400;
  }
  .ip-box strong { font-weight: 600; font-size: 15px; }

  label {
    display: block;
    font-size: 14px;
    font-weight: 400;
    color: var(--text-heading);
    margin-bottom: 8px;
  }

  .options {
    display: flex;
    flex-direction: column;
    gap: 12px;
    margin-bottom: 24px;
  }

  .option {
    display: flex;
    align-items: flex-start;
    gap: 12px;
    padding: 14px 16px;
    border: 1px solid var(--border-color);
    border-radius: var(--border-radius);
    cursor: pointer;
    transition: border-color 0.2s, background-color 0.2s;
    background-color: #ffffff;
  }
  .option:hover {
    border-color: var(--brand-primary);
  }
  .option input[type=radio] {
    accent-color: var(--brand-primary);
    width: 16px;
    height: 16px;
    margin-top: 2px;
  }
  .option.selected {
    border-color: var(--brand-primary);
    background-color: #f4f9ff;
  }
  .option-label {
    font-size: 14px;
    color: var(--text-heading);
    font-weight: 500;
  }
  .option-desc {
    font-size: 12.5px;
    color: var(--text-muted);
    margin-top: 3px;
    line-height: 17px;
  }

  #domain-section { display: none; margin-bottom: 24px; }
  #domain-section.visible { display: block; }

  input[type=text] {
    width: 100%;
    height: 40px;
    padding: 0 14px;
    border: 1px solid var(--border-color);
    border-radius: 6px;
    font-size: 14px;
    color: var(--text-main);
    outline: none;
    transition: border-color 0.15s;
    font-family: var(--font-family-base);
    background-color: #ffffff;
  }
  input[type=text]:focus {
    border-color: var(--brand-primary);
  }
  input[type=text]::placeholder {
    color: #b3b5b9;
  }

  .dns-info {
    background: #f0f7ff;
    border: 1px solid #bcd7ff;
    border-radius: 6px;
    padding: 14px 16px;
    margin-top: 14px;
    font-size: 13px;
    color: #1a4f8a;
    line-height: 18px;
  }
  .dns-info code { background: #dbeafe; padding: 2px 6px; border-radius: 4px; font-family: monospace; font-size: 12px; color: #1e40af; }
  .dns-table { width: 100%; margin-top: 10px; border-collapse: collapse; }
  .dns-table td { padding: 5px 4px; font-size: 13px; color: #1a4f8a; }
  .dns-table td:first-child { font-weight: 600; width: 70px; }

  .lu-btn--plain.lu-btn--primary {
    cursor: pointer;
    box-sizing: border-box;
    font-family: var(--font-family-base);
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    transition: background-color 0.15s, border-color 0.15s;
    vertical-align: top;
    white-space: nowrap;
    outline: 0;
    font-weight: 500;
    border-radius: 6px;
    font-size: 14px;
    height: 40px;
    padding: 0 16px;
    color: #ffffff;
    background-color: var(--brand-primary);
    border: 1px solid var(--brand-primary);
    width: 100%;
  }
  .lu-btn--plain.lu-btn--primary:hover {
    background-color: var(--brand-primary-hover);
    border-color: var(--brand-primary-hover);
  }
  .lu-btn--plain.lu-btn--primary:disabled {
    background-color: #dadde6;
    border-color: #dadde6;
    cursor: not-allowed;
  }
  .lu-btn__icon { margin-right: 6px; font-size: 18px; display: inline-flex; align-items: center; }
  .lu-btn__text { display: inline-block; line-height: 1; }

  .note { font-size: 12px; color: var(--text-muted); text-align: center; margin-top: 16px; }
  .spinner { display: block; width: 44px; height: 44px; border: 3px solid #edeff2; border-top-color: var(--brand-primary); border-radius: 50%; animation: spin 0.8s linear infinite; margin: 0 auto 24px; }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
</head>
<body>
<div class="card">
  <div id="setup-content">
    <h1>Instalace n8n</h1>
    <p class="subtitle">Nakonfigurujte přístupovou adresu vašeho n8n serveru.</p>
    <div class="ip-box">IP adresa tohoto serveru: <strong>SERVER_IP_PLACEHOLDER</strong></div>
    <label>Jak chcete přistupovat k n8n?</label>
    <div class="options">
      <label class="option selected" id="opt-ip">
        <input type="radio" name="mode" value="ip" checked onchange="selectMode('ip')">
        <div>
          <div class="option-label">Použít IP adresu</div>
          <div class="option-desc">Rychlé, bez nastavení DNS. Bude použit self-signed certifikát.</div>
        </div>
      </label>
      <label class="option" id="opt-domain">
        <input type="radio" name="mode" value="domain" onchange="selectMode('domain')">
        <div>
          <div class="option-label">Použít vlastní doménu</div>
          <div class="option-desc">Doporučeno. Automatický HTTPS certifikát přes Let's Encrypt.</div>
        </div>
      </label>
    </div>
    <div id="domain-section">
      <div style="margin-bottom: 16px;">
        <label for="domain">Vaše doména</label>
        <input type="text" id="domain" placeholder="n8n.vasestranka.cz" oninput="updateDns(this.value)">
        <div class="dns-info">
          Před pokračováním nastavte DNS záznam:
          <table class="dns-table">
            <tr><td>Typ</td><td><code>A</code></td></tr>
            <tr><td>Název</td><td><code id="dns-name">n8n.vasestranka.cz</code></td></tr>
            <tr><td>Hodnota</td><td><code>SERVER_IP_PLACEHOLDER</code></td></tr>
            <tr><td>TTL</td><td><code>300</code></td></tr>
          </table>
        </div>
      </div>
      <div style="margin-bottom: 4px;">
        <label for="email">E-mail pro Let's Encrypt</label>
        <input type="text" id="email" placeholder="vas@email.cz">
      </div>
    </div>

    <button id="btn" type="button" class="lu-btn lu-btn--plain lu-btn--primary" onclick="handleSubmit()">
      <i class="lu-mdi mdi mdi-plus lu-btn__icon"></i>
      <span class="lu-btn__text" id="btn-text">Pokračovat v instalaci</span>
    </button>

    <p class="note">Po potvrzení bude instalace pokračovat automaticky.</p>
  </div>
</div>
<script>
function selectMode(mode) {
  document.getElementById('opt-ip').classList.toggle('selected', mode === 'ip');
  document.getElementById('opt-domain').classList.toggle('selected', mode === 'domain');
  document.getElementById('domain-section').classList.toggle('visible', mode === 'domain');
}
function updateDns(value) {
  document.getElementById('dns-name').textContent = value || 'n8n.vasestranka.cz';
}
function getSuccessHTML(host) {
  return '<div style="text-align:center; padding: 10px 0;"><div class="spinner"></div><h1>Instalace probíhá</h1><p style="color:var(--text-muted); font-size:14px; line-height: 1.6; margin-top: 12px;">Server se nyní konfiguruje. Za několik minut bude n8n dostupné na <br><strong style="color:var(--brand-primary); font-weight:600;">https://' + host + '</strong>.<br><br>Tuto stránku můžete bezpečně zavřít.</p></div>';
}
function handleSubmit() {
  var mode = document.querySelector('input[name=mode]:checked').value;
  var domain = document.getElementById('domain').value.trim();
  var email = document.getElementById('email').value.trim();
  if (mode === 'domain') {
    if (!domain) { alert('Zadejte doménu.'); return; }
    if (!email) { alert('Zadejte e-mail pro Let\'s Encrypt.'); return; }
  }
  var host = mode === 'ip' ? 'SERVER_IP_PLACEHOLDER' : domain;
  var btn = document.getElementById('btn');
  var btnText = document.getElementById('btn-text');
  btnText.textContent = 'Ověřuji...';
  btn.disabled = true;
  fetch('/submit', {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: 'host=' + encodeURIComponent(host) + '&email=' + encodeURIComponent(email)
  }).then(function(r) {
    if (r.ok) {
      document.getElementById('setup-content').innerHTML = getSuccessHTML(host);
    } else {
      r.text().then(function(err) {
        btnText.textContent = 'Pokračovat v instalaci';
        btn.disabled = false;
        if (err.indexOf('DNS_MISMATCH') === 0) {
          var resolved = err.split(':')[1];
          alert('Doména ' + host + ' směřuje na ' + resolved + ', ale IP tohoto serveru je SERVER_IP_PLACEHOLDER.\n\nZkontrolujte DNS záznam and zkuste znovu.');
        } else if (err === 'DNS_UNRESOLVED') {
          alert('Domenou ' + host + ' se nepodařilo přeložit.\n\nZkontrolujte DNS záznam. Změny DNS mohou trvat až 24 hodin.');
        }
      });
    }
  });
}
</script>
</body>
</html>
HTML

  sed -i "s/SERVER_IP_PLACEHOLDER/$DETECTED_IP/g" /tmp/setup.html

  cat > /tmp/n8n_setup_server.py << 'PYEOF'
import http.server, ssl, urllib.parse, os, re, socket, sys
SERVER_IP = open('/tmp/setup_ip').read().strip()
HTML = open('/tmp/setup.html').read()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if os.path.exists('/tmp/n8n_config'):
            host = "server"
            try:
                with open('/tmp/n8n_config', 'r') as f:
                    for line in f:
                        if line.startswith('N8N_HOST='):
                            host = line.split('=')[1].strip()
            except:
                pass

            success_content = '<div style="text-align:center; padding: 10px 0;"><div class="spinner"></div><h1>Instalace probíhá</h1><p style="color:var(--text-muted); font-size:14px; line-height: 1.6; margin-top: 12px;">Server se nyní konfiguruje. Za několik minut bude n8n dostupné na <br><strong style="color:var(--brand-primary); font-weight:600;">https://' + host + '</strong>.<br><br>Tuto stránku můžete bezpečně zavřít.</p></div>'

            page = re.sub(
                r'<div id="setup-content">.*?</div>\s*</div>\s*<script>',
                '<div id="setup-content">' + success_content + '</div></div><script>',
                HTML,
                flags=re.DOTALL
            )
        else:
            page = HTML

        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(page.encode())
    def do_POST(self):
        if self.path == '/submit':
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode()
            params = urllib.parse.parse_qs(body)
            host = params.get('host', [''])[0]
            email = params.get('email', [''])[0]
            is_ip = bool(re.match(r'^\d+\.\d+\.\d+\.\d+$', host))
            if not is_ip:
                try:
                    resolved = socket.gethostbyname(host)
                    if resolved != SERVER_IP:
                        self.send_response(400)
                        self.send_header('Content-Type', 'text/plain')
                        self.end_headers()
                        self.wfile.write(('DNS_MISMATCH:' + resolved).encode())
                        return
                except socket.gaierror:
                    self.send_response(400)
                    self.send_header('Content-Type', 'text/plain')
                    self.end_headers()
                    self.wfile.write(b'DNS_UNRESOLVED')
                    return
            with open('/tmp/n8n_config', 'w') as f:
                f.write('N8N_HOST=' + host + '\nN8N_EMAIL=' + email + '\n')
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'ok')
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(('0.0.0.0', 443), Handler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain('/tmp/setup.crt', '/tmp/setup.key')
server.socket = ctx.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PYEOF

  echo "$DETECTED_IP" > /tmp/setup_ip
  python3 /tmp/n8n_setup_server.py &
  WEBSERVER_PID=$!

  info "Otevři v prohlížeči: https://$DETECTED_IP"
  info "Čekám na konfiguraci..."

  while [[ ! -f /tmp/n8n_config ]]; do
    sleep 2
  done

  source /tmp/n8n_config
  rm -f /tmp/n8n_setup_server.py /tmp/setup.html /tmp/setup.crt /tmp/setup.key /tmp/setup_ip
fi

if [[ "$N8N_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  USE_DOMAIN=false
else
  USE_DOMAIN=true
  LETSENCRYPT_EMAIL="${N8N_EMAIL:-}"
  [[ -z "$LETSENCRYPT_EMAIL" ]] && error "E-mail pro Let's Encrypt chybí."
fi

if [[ -z "${DB_PASS:-}" ]]; then
  DB_PASS=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
fi

# Použij starý klíč, pokud existuje, jinak vygeneruj nový
if [[ -n "$EXISTING_KEY" ]]; then
  N8N_ENCRYPTION_KEY="$EXISTING_KEY"
else
  N8N_ENCRYPTION_KEY=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)
fi

info "Instalace závislostí..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q curl ca-certificates ufw nginx
if [[ "$USE_DOMAIN" == true ]]; then
  apt-get install -y -q certbot python3-certbot-nginx
fi
log "Závislosti nainstalovány."

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

info "Instalace Node.js 22 LTS..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
apt-get install -y -q nodejs
log "Node.js $(node --version) nainstalován."

info "Instalace n8n..."
if ! id "n8n" &>/dev/null; then
  useradd --system --shell /usr/sbin/nologin --create-home --home-dir /opt/n8n n8n
fi
npm install -g npm@latest
npm install -g n8n
mkdir -p /opt/n8n/.n8n
chown -R n8n:n8n /opt/n8n
log "n8n nainstalován."

info "Vytváření konfigurace..."
mkdir -p /etc/n8n
chmod 750 /etc/n8n

cat > /etc/n8n/n8n.env <<EOF
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=localhost
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=${DB_NAME}
DB_POSTGRESDB_USER=${DB_USER}
DB_POSTGRESDB_PASSWORD=${DB_PASS}

N8N_HOST=${N8N_HOST}
N8N_PORT=5678
N8N_PROTOCOL=https
WEBHOOK_URL=https://${N8N_HOST}/

N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_SECURE_COOKIE=true

N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console
N8N_USER_FOLDER=/opt/n8n/.n8n
N8N_DIAGNOSTICS_ENABLED=false
EOF

chmod 600 /etc/n8n/n8n.env
chown root:root /etc/n8n/n8n.env
log "Konfigurace uložena."

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

if [[ -n "${WEBSERVER_PID:-}" ]]; then
  kill $WEBSERVER_PID 2>/dev/null || true
  wait $WEBSERVER_PID 2>/dev/null || true
fi

info "Konfigurace Nginx..."

if [[ "$USE_DOMAIN" == false ]]; then
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/ssl/private/n8n-selfsigned.key \
    -out /etc/ssl/certs/n8n-selfsigned.crt \
    -subj "/CN=${N8N_HOST}/O=n8n/C=CZ" \
    -addext "subjectAltName=IP:${N8N_HOST}" 2>/dev/null
fi

cat > /etc/nginx/sites-available/n8n << 'NGINXEOF'
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}
NGINXEOF

if [[ "$USE_DOMAIN" == false ]]; then
cat >> /etc/nginx/sites-available/n8n <<EOF
server {
    listen 80;
    server_name ${N8N_HOST};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${N8N_HOST};
    ssl_certificate /etc/ssl/certs/n8n-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/n8n-selfsigned.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
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
else
cat >> /etc/nginx/sites-available/n8n <<EOF
# 1. Catch-all blok pro HTTP IP přístupy včetně zachování cest (např. /setup)
server {
    listen 80 default_server;
    server_name _;
    return 301 https://${N8N_HOST}\$request_uri;
}

# 2. Primární HTTP konfigurace domény pro potřeby Certbotu
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
    }
}
EOF
fi

ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl enable nginx && systemctl restart nginx
log "Nginx nakonfigurován."

info "Konfigurace firewallu..."
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
log "Firewall aktivován."

if [[ "$USE_DOMAIN" == true ]]; then
  info "Získávám SSL certifikát..."
  certbot --nginx --non-interactive --agree-tos \
    --email "$LETSENCRYPT_EMAIL" \
    --domains "$N8N_HOST" \
    --redirect
  log "HTTPS certifikát nainstalován."

  # 3. Dodatečné provázání HTTPS IP přístupů pro bezpečné přesměrování URI cest na doménu
  cat >> /etc/nginx/sites-available/n8n <<EOF

server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/letsencrypt/live/${N8N_HOST}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${N8N_HOST}/privkey.pem;
    return 301 https://${N8N_HOST}\$request_uri;
}
EOF
  nginx -t && systemctl restart nginx
fi

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

echo ""
echo "Instalace dokončena."
echo ""
echo "  URL:             https://${N8N_HOST}"
echo ""
echo "  Logy:            journalctl -u n8n -f"
echo "  Restart:         systemctl restart n8n"
echo "  Aktualizace:     npm update -g n8n"
echo ""
echo "  Konfig:          /etc/n8n/n8n.env  (root only)"
echo "  DB heslo:        ${DB_PASS}"
echo "  Encryption key:  ${N8N_ENCRYPTION_KEY}"
echo ""

# Kompletní pročištění dočasných konfiguračních souborů
rm -f /tmp/n8n_config /tmp/setup.crt /tmp/setup.key /tmp/setup.html /tmp/setup_ip

apt-get autoremove -y
apt-get autoclean -y
apt-get clean
rm -rf /var/lib/apt/lists/*

# Úplné samo-odstranění skriptu bez vyvolání chyb na pozadí
SCRIPT_PATH="$(readlink -f "$0")"
(
    sleep 2
    rm -f "$SCRIPT_PATH"
) &>/dev/null &