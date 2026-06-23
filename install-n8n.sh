#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[OK]${NC} $1"; }
info()  { echo -e "${BLUE}[..]${NC} $1"; }
error() { echo -e "${RED}[!!]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && error "Spusť jako root: sudo bash install-n8n.sh"

DB_NAME="n8n"
DB_USER="n8n"

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

  # Zapiš HTML do souboru (ne f-string, čisté závorky)
  cat > /tmp/setup.html << HTML
<!DOCTYPE html>
<html lang="cs">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Instalace n8n</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f5f5f5; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 20px; }
  .card { background: white; border-radius: 12px; padding: 40px; max-width: 520px; width: 100%; box-shadow: 0 4px 24px rgba(0,0,0,0.08); }
  h1 { font-size: 22px; color: #1a1a1a; margin-bottom: 8px; }
  .subtitle { color: #666; font-size: 14px; margin-bottom: 32px; }
  .ip-box { background: #f0f7ff; border: 1px solid #c2deff; border-radius: 8px; padding: 12px 16px; margin-bottom: 28px; font-size: 14px; color: #1a4a8a; }
  .ip-box strong { font-size: 18px; letter-spacing: 0.5px; }
  label { display: block; font-size: 13px; font-weight: 600; color: #444; margin-bottom: 6px; }
  .options { display: flex; flex-direction: column; gap: 10px; margin-bottom: 24px; }
  .option { display: flex; align-items: center; gap: 10px; padding: 12px 16px; border: 2px solid #e0e0e0; border-radius: 8px; cursor: pointer; transition: border-color 0.2s; }
  .option:hover { border-color: #666; }
  .option input[type=radio] { accent-color: #ff6d5a; width: 16px; height: 16px; }
  .option.selected { border-color: #ff6d5a; background: #fff8f7; }
  .option-label { font-size: 14px; color: #333; }
  .option-desc { font-size: 12px; color: #888; margin-top: 2px; }
  #domain-section { display: none; margin-bottom: 24px; }
  #domain-section.visible { display: block; }
  input[type=text] { width: 100%; padding: 10px 14px; border: 2px solid #e0e0e0; border-radius: 8px; font-size: 14px; outline: none; transition: border-color 0.2s; }
  input[type=text]:focus { border-color: #ff6d5a; }
  .dns-info { background: #fffbea; border: 1px solid #ffe57a; border-radius: 8px; padding: 14px 16px; margin-top: 14px; font-size: 13px; color: #7a5c00; }
  .dns-info code { background: #fff3cc; padding: 2px 6px; border-radius: 4px; font-family: monospace; }
  .dns-table { width: 100%; margin-top: 10px; border-collapse: collapse; }
  .dns-table td { padding: 4px 8px; font-size: 12px; }
  .dns-table td:first-child { font-weight: 600; width: 80px; }
  button { width: 100%; padding: 14px; background: #ff6d5a; color: white; border: none; border-radius: 8px; font-size: 15px; font-weight: 600; cursor: pointer; transition: background 0.2s; }
  button:hover { background: #e55a47; }
  button:disabled { background: #ccc; cursor: not-allowed; }
  .note { font-size: 12px; color: #999; text-align: center; margin-top: 16px; }
  .spinner { display: none; width: 40px; height: 40px; border: 4px solid #f0f0f0; border-top-color: #ff6d5a; border-radius: 50%; animation: spin 0.8s linear infinite; margin: 0 auto 24px; }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
</head>
<body>
<div class="card">
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
    <div style="margin-top:12px;">
      <label for="email">E-mail pro Let's Encrypt</label>
      <input type="text" id="email" placeholder="vas@email.cz" style="margin-top:6px;">
    </div>
  </div>
  <button id="btn" onclick="handleSubmit()">Pokračovat v instalaci</button>
  <p class="note">Po potvrzení bude instalace pokračovat automaticky.</p>
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
  btn.textContent = 'Ověřuji...';
  btn.disabled = true;

  fetch('/submit', {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: 'host=' + encodeURIComponent(host) + '&email=' + encodeURIComponent(email)
  }).then(function(r) {
    if (r.ok) {
      document.querySelector('.card').innerHTML = '<div style="text-align:center"><div class="spinner" style="display:block"></div><h1 style="margin-bottom:16px">Instalace probíhá</h1><p style="color:#666;font-size:14px">Server se nyní konfiguruje. Za několik minut bude n8n dostupné na <strong>https://' + host + '</strong>.<br><br>Tuto stránku můžete zavřít.</p></div>';
    } else {
      r.text().then(function(err) {
        btn.textContent = 'Pokračovat v instalaci';
        btn.disabled = false;
        if (err.indexOf('DNS_MISMATCH') === 0) {
          var resolved = err.split(':')[1];
          alert('Doména ' + host + ' směřuje na ' + resolved + ', ale IP tohoto serveru je SERVER_IP_PLACEHOLDER.\n\nZkontrolujte DNS záznam a zkuste znovu.');
        } else if (err === 'DNS_UNRESOLVED') {
          alert('Doménu ' + host + ' se nepodařilo přeložit.\n\nZkontrolujte DNS záznam. Změny DNS mohou trvat až 24 hodin.');
        }
      });
    }
  });
}
</script>
</body>
</html>
HTML

  # Nahraď placeholder skutečnou IP
  sed -i "s/SERVER_IP_PLACEHOLDER/$DETECTED_IP/g" /tmp/setup.html

  cat > /tmp/n8n_setup_server.py << 'PYEOF'
import http.server, ssl, urllib.parse, os, re, socket, sys

SERVER_IP = open('/tmp/setup_ip').read().strip()
HTML = open('/tmp/setup.html').read()
WAITING_HTML = """<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"><title>Instalace n8n</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:sans-serif;background:#f5f5f5;display:flex;align-items:center;justify-content:center;min-height:100vh}.card{background:white;border-radius:12px;padding:40px;max-width:520px;width:100%;box-shadow:0 4px 24px rgba(0,0,0,.08);text-align:center}h1{font-size:22px;margin-bottom:16px}p{color:#666;font-size:14px;line-height:1.6}.spinner{width:40px;height:40px;border:4px solid #f0f0f0;border-top-color:#ff6d5a;border-radius:50%;animation:spin .8s linear infinite;margin:0 auto 24px}@keyframes spin{to{transform:rotate(360deg)}}</style>
</head><body><div class="card"><div class="spinner"></div><h1>Instalace probíhá</h1><p>Server se nyní konfiguruje. Za několik minut bude n8n dostupné.<br><br>Tuto stránku můžete zavřít.</p></div></body></html>"""

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        page = WAITING_HTML if os.path.exists('/tmp/n8n_config') else HTML
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
  # n8n_config nesmazáváme - webserver ho potřebuje pro waiting stránku při refreshi

  log "Konfigurace přijata: $N8N_HOST"
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

N8N_ENCRYPTION_KEY=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)

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

info "Instalace Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
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

# Zastav konfigurační webserver před spuštěním nginx (oba by chtěly port 443)
if [[ -n "${WEBSERVER_PID:-}" ]]; then
  rm -f /tmp/n8n_config
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