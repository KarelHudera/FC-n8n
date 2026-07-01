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

SETUP_USER="${SETUP_USER:-n8n}"
SETUP_PASS_HASH="${SETUP_PASS_HASH:-}"

[[ -z "$SETUP_PASS_HASH" ]] && error "SETUP_PASS_HASH není nastaven. Předej SHA-256 crypt hash hesla."
[[ "$SETUP_PASS_HASH" != \$5\$* ]] && error "SETUP_PASS_HASH musí být SHA-256 crypt hash (začíná \$5\$)."

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

  openssl req -x509 -nodes -days 7 -newkey rsa:2048 \
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
    --body-bg: #ffffff;
    --card-bg: #ffffff;
    --border-color: #DADDE6;
    --border-color-light: #EFEFF1;
    --text-main: #4B4F58;
    --text-heading: #17191C;
    --text-muted: #6D7482;
    --brand-primary: #069bfe;
    --brand-primary-hover: #058ae2;
    --brand-primary-faded: #E5EFFF;
    --border-radius: 12px;
    --border-radius-sm: 6px;
    --box-shadow-card: 0px 0px 1px rgba(0,0,0,.04), 0px 2px 24px rgba(0,0,0,.08);
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: var(--font-family-base);
    background-color: var(--body-bg);
    display: flex; align-items: center; justify-content: center;
    min-height: 100vh; padding: 20px;
    color: var(--text-main);
    -webkit-font-smoothing: antialiased;
  }
  .card {
    background: var(--card-bg);
    border-radius: var(--border-radius);
    padding: 36px; max-width: 500px; width: 100%;
    border: 1px solid var(--border-color-light);
    box-shadow: var(--box-shadow-card);
  }
  h1 { font-size: 24px; color: var(--text-heading); margin-bottom: 6px; font-weight: 500; letter-spacing: -0.3px; }
  .subtitle { color: var(--text-muted); font-size: 13.5px; margin-bottom: 28px; font-weight: 400; }
  .ip-box {
    background: var(--brand-primary-faded); border-radius: var(--border-radius-sm);
    padding: 14px 18px; margin-bottom: 24px; font-size: 14px; color: #2368AD;
  }
  .ip-box strong { font-weight: 600; font-size: 15px; }
  label { display: block; font-size: 14px; font-weight: 400; color: var(--text-heading); margin-bottom: 8px; }
  .options { display: flex; flex-direction: column; gap: 12px; margin-bottom: 24px; }
  .option {
    display: flex; align-items: flex-start; gap: 12px; padding: 14px 16px;
    border: 1px solid var(--border-color); border-radius: var(--border-radius-sm);
    cursor: pointer; transition: border-color .15s, background-color .15s;
    background-color: #ffffff; position: relative;
  }
  .option:hover { border-color: #C5C9D1; }
  .option input[type=radio] { position: absolute; opacity: 0; width: 0; height: 0; }
  .radio-circle {
    flex: 0 0 18px; width: 18px; height: 18px; border-radius: 50%;
    border: 2px solid var(--border-color); margin-top: 2px; position: relative;
    transition: border-color .15s, background-color .15s; background: #fff;
  }
  .option:hover .radio-circle { border-color: var(--brand-primary); }
  .option.selected .radio-circle { border-color: var(--brand-primary); background: var(--brand-primary); }
  .option.selected .radio-circle::after {
    content: ""; position: absolute; top: 50%; left: 50%;
    width: 6px; height: 6px; border-radius: 50%; background: #fff;
    transform: translate(-50%, -50%);
  }
  .option-label { font-size: 14px; color: var(--text-heading); font-weight: 500; }
  .option-desc { font-size: 12.5px; color: var(--text-muted); margin-top: 3px; line-height: 17px; }
  #domain-section { display: none; margin-bottom: 24px; }
  #domain-section.visible { display: block; }
  #update-schedule { display: none; margin-bottom: 24px; }
  #update-schedule.visible { display: block; }
  .form-row { margin-bottom: 16px; }
  .form-row-inline { display: flex; gap: 12px; margin-bottom: 16px; }
  .form-row-inline > div { flex: 1; }
  input[type=text], select {
    width: 100%; height: 44px; padding: 0 14px;
    border: 1px solid var(--border-color); border-radius: var(--border-radius-sm);
    font-size: 14px; color: var(--text-main); outline: none;
    transition: border-color .15s; font-family: var(--font-family-base);
    background-color: #ffffff; appearance: none;
  }
  input[type=text]:hover, select:hover { border-color: #C5C9D1; }
  input[type=text]:focus, select:focus { border-color: var(--brand-primary); }
  input[type=text]::placeholder { color: #b3b5b9; }
  .select-wrap { position: relative; }
  .select-wrap::after {
    content: ""; position: absolute; right: 14px; top: 50%;
    transform: translateY(-50%); width: 0; height: 0;
    border-left: 5px solid transparent; border-right: 5px solid transparent;
    border-top: 6px solid var(--text-muted); pointer-events: none;
  }
  .dns-info {
    background: #f0f7ff; border: 1px solid #bcd7ff;
    border-radius: var(--border-radius-sm); padding: 14px 16px;
    margin-top: 14px; font-size: 13px; color: #1a4f8a; line-height: 18px;
  }
  .dns-info code { background: #dbeafe; padding: 2px 6px; border-radius: 4px; font-family: monospace; font-size: 12px; color: #1e40af; }
  .dns-table { width: 100%; margin-top: 10px; border-collapse: collapse; }
  .dns-table td { padding: 5px 4px; font-size: 13px; color: #1a4f8a; }
  .dns-table td:first-child { font-weight: 600; width: 70px; }
  .btn {
    cursor: pointer; font-family: var(--font-family-base); display: inline-flex;
    align-items: center; justify-content: center; transition: background-color .15s, border-color .15s;
    white-space: nowrap; outline: 0; font-weight: 500;
    border-radius: var(--border-radius-sm); font-size: 14px;
    height: 44px; padding: 0 16px; width: 100%;
  }
  .btn-primary { color: #fff; background-color: var(--brand-primary); border: 1px solid var(--brand-primary); }
  .btn-primary:hover { background-color: var(--brand-primary-hover); border-color: var(--brand-primary-hover); }
  .btn-primary:disabled { background-color: #DADDE6; border-color: #DADDE6; cursor: not-allowed; }
  .btn-secondary { color: var(--text-main); background-color: #fff; border: 1px solid var(--border-color); margin-bottom: 10px; }
  .btn-secondary:hover { border-color: #C5C9D1; background-color: #f9f9f9; }
  .btn-icon { margin-right: 6px; font-size: 18px; display: inline-flex; align-items: center; }
  .back-link {
    display: inline-flex; align-items: center; gap: 4px;
    font-size: 13px; color: var(--text-muted); cursor: pointer;
    margin-bottom: 20px; background: none; border: none; padding: 0;
    font-family: var(--font-family-base);
  }
  .back-link:hover { color: var(--text-main); }
  .note { font-size: 12px; color: var(--text-muted); text-align: center; margin-top: 16px; }
  .spinner { display: block; width: 44px; height: 44px; border: 3px solid #edeff2; border-top-color: var(--brand-primary); border-radius: 50%; animation: spin .8s linear infinite; margin: 0 auto 24px; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .page { display: none; }
  .page.active { display: block; }
</style>
</head>
<body>
<div class="card">

  <!-- STRÁNKA 1: Volba přístupu -->
  <div id="page1" class="page active">
    <h1>Instalace n8n</h1>
    <p class="subtitle">Nakonfigurujte přístupovou adresu vašeho n8n serveru.</p>
    <div class="ip-box">IP adresa tohoto serveru: <strong>SERVER_IP_PLACEHOLDER</strong></div>
    <label>Jak chcete přistupovat k n8n?</label>
    <div class="options">
      <label class="option selected" id="opt-ip">
        <input type="radio" name="mode" value="ip" checked onchange="selectMode('ip')">
        <span class="radio-circle"></span>
        <div>
          <div class="option-label">Použít IP adresu</div>
          <div class="option-desc">Rychlé, bez nastavení DNS. Bude použit self-signed certifikát.</div>
        </div>
      </label>
      <label class="option" id="opt-domain">
        <input type="radio" name="mode" value="domain" onchange="selectMode('domain')">
        <span class="radio-circle"></span>
        <div>
          <div class="option-label">Použít vlastní doménu</div>
          <div class="option-desc">Doporučeno. Automatický HTTPS certifikát přes Let's Encrypt.</div>
        </div>
      </label>
    </div>
    <div id="domain-section">
      <div class="form-row">
        <label for="domain">Vaše doména</label>
        <input type="text" id="domain" placeholder="n8n.vasestranka.cz" oninput="updateDns(this.value)">
        <div class="dns-info">
          Před pokračováním nastavte DNS záznam:
          <table class="dns-table">
            <tr><td>Typ</td><td><code>A</code></td></tr>
            <tr><td>Název</td><td><code id="dns-name">n8n.vasestranka.cz</code></td></tr>
            <tr><td>Hodnota</td><td><code>SERVER_IP_PLACEHOLDER</code></td></tr>
            <tr><td>TTL</td><td><code>3600</code></td></tr>
          </table>
        </div>
      </div>
      <div class="form-row">
        <label for="email">E-mail pro Let's Encrypt</label>
        <input type="text" id="email" placeholder="vas@email.cz">
      </div>
    </div>
    <button id="btn-next" type="button" class="btn btn-primary" onclick="goToPage2()">
      <i class="mdi mdi-arrow-right btn-icon"></i>
      <span>Pokračovat</span>
    </button>
  </div>

  <!-- STRÁNKA 2: Automatické aktualizace -->
  <div id="page2" class="page">
    <button class="back-link" onclick="goToPage1()">
      <i class="mdi mdi-arrow-left"></i> Zpět
    </button>
    <h1>Automatické aktualizace</h1>
    <p class="subtitle">Nastavte plán automatické aktualizace n8n na nejnovější stabilní verzi.</p>
    <div class="options" style="margin-bottom: 24px;">
      <div class="option" id="opt-none" onclick="selectUpdate('none')">
        <span class="radio-circle" id="rc-none"></span>
        <div>
          <div class="option-label">Bez automatických aktualizací</div>
          <div class="option-desc">Aktualizace provedu ručně příkazem <span style="background:#f1f3f5;padding:1px 5px;border-radius:3px;font-family:monospace;font-size:11px;">npm install -g n8n@latest</span></div>
        </div>
      </div>
      <div class="option" id="opt-weekly" onclick="selectUpdate('weekly')">
        <span class="radio-circle" id="rc-weekly"></span>
        <div>
          <div class="option-label">Týdně</div>
          <div class="option-desc">Aktualizace jednou týdně ve vybraný den a čas.</div>
        </div>
      </div>
      <div class="option" id="opt-monthly" onclick="selectUpdate('monthly')">
        <span class="radio-circle" id="rc-monthly"></span>
        <div>
          <div class="option-label">Měsíčně</div>
          <div class="option-desc">Aktualizace jednou měsíčně ve vybraný den a čas.</div>
        </div>
      </div>
    </div>

    <!-- Plán pro týdenní aktualizace -->
    <div id="schedule-weekly" class="update-schedule" style="display:none; margin-bottom:24px;">
      <div class="form-row-inline">
        <div>
          <label>Den v týdnu</label>
          <div class="select-wrap">
            <select id="weekly-day">
              <option value="1">Pondělí</option>
              <option value="2">Úterý</option>
              <option value="3">Středa</option>
              <option value="4">Čtvrtek</option>
              <option value="5">Pátek</option>
              <option value="6">Sobota</option>
              <option value="0">Neděle</option>
            </select>
          </div>
        </div>
        <div>
          <label>Čas</label>
          <div class="select-wrap">
            <select id="weekly-hour">
              <option value="0">00:00</option>
              <option value="1">01:00</option>
              <option value="2">02:00</option>
              <option value="3" selected>03:00</option>
              <option value="4">04:00</option>
              <option value="5">05:00</option>
              <option value="6">06:00</option>
              <option value="7">07:00</option>
              <option value="8">08:00</option>
              <option value="9">09:00</option>
              <option value="10">10:00</option>
              <option value="11">11:00</option>
              <option value="12">12:00</option>
              <option value="13">13:00</option>
              <option value="14">14:00</option>
              <option value="15">15:00</option>
              <option value="16">16:00</option>
              <option value="17">17:00</option>
              <option value="18">18:00</option>
              <option value="19">19:00</option>
              <option value="20">20:00</option>
              <option value="21">21:00</option>
              <option value="22">22:00</option>
              <option value="23">23:00</option>
            </select>
          </div>
        </div>
      </div>
    </div>

    <!-- Plán pro měsíční aktualizace -->
    <div id="schedule-monthly" class="update-schedule" style="display:none; margin-bottom:24px;">
      <div class="form-row-inline">
        <div>
          <label>Den v měsíci</label>
          <div class="select-wrap">
            <select id="monthly-day">
              <option value="1">1.</option>
              <option value="2">2.</option>
              <option value="3">3.</option>
              <option value="4">4.</option>
              <option value="5">5.</option>
              <option value="7">7.</option>
              <option value="10">10.</option>
              <option value="14">14.</option>
              <option value="15">15.</option>
              <option value="20">20.</option>
              <option value="28">28.</option>
            </select>
          </div>
        </div>
        <div>
          <label>Čas</label>
          <div class="select-wrap">
            <select id="monthly-hour">
              <option value="0">00:00</option>
              <option value="1">01:00</option>
              <option value="2">02:00</option>
              <option value="3" selected>03:00</option>
              <option value="4">04:00</option>
              <option value="5">05:00</option>
              <option value="6">06:00</option>
              <option value="7">07:00</option>
              <option value="8">08:00</option>
              <option value="9">09:00</option>
              <option value="10">10:00</option>
              <option value="11">11:00</option>
              <option value="12">12:00</option>
              <option value="13">13:00</option>
              <option value="14">14:00</option>
              <option value="15">15:00</option>
              <option value="16">16:00</option>
              <option value="17">17:00</option>
              <option value="18">18:00</option>
              <option value="19">19:00</option>
              <option value="20">20:00</option>
              <option value="21">21:00</option>
              <option value="22">22:00</option>
              <option value="23">23:00</option>
            </select>
          </div>
        </div>
      </div>
    </div>

    <button id="btn-install" type="button" class="btn btn-primary" onclick="handleSubmit()">
      <i class="mdi mdi-check btn-icon"></i>
      <span id="btn-install-text">Spustit instalaci</span>
    </button>
    <p class="note">Po potvrzení bude instalace pokračovat automaticky.</p>
  </div>

  <!-- STRÁNKA 3: Probíhá instalace -->
  <div id="page3" class="page">
    <div style="text-align:center; padding: 10px 0;">
      <div class="spinner"></div>
      <h1>Instalace probíhá</h1>
      <p style="color:var(--text-muted); font-size:14px; line-height: 1.6; margin-top: 12px;">
        Server se nyní konfiguruje. Za několik minut bude n8n dostupné na<br>
        <strong id="final-url" style="color:var(--brand-primary); font-weight:600;"></strong>.<br><br>
        Tuto stránku můžete bezpečně zavřít.
      </p>
    </div>
  </div>

</div>
<script>
var selectedHost = sessionStorage.getItem('n8nHost') || '';
var selectedEmail = sessionStorage.getItem('n8nEmail') || '';
var currentUpdate = 'none';

// Obnova stránky po refreshi
(function() {
  var page = sessionStorage.getItem('n8nPage');
  if (page === '2') {
    showPage('page2');
    selectUpdate('none');
  } else if (page === '3') {
    showPage('page3');
    var url = sessionStorage.getItem('n8nHost');
    if (url) document.getElementById('final-url').textContent = 'https://' + url;
  }
})();

function showPage(id) {
  ['page1','page2','page3'].forEach(function(p) {
    document.getElementById(p).classList.remove('active');
  });
  document.getElementById(id).classList.add('active');
}

function selectMode(mode) {
  document.getElementById('opt-ip').classList.toggle('selected', mode === 'ip');
  document.getElementById('opt-domain').classList.toggle('selected', mode === 'domain');
  document.getElementById('domain-section').classList.toggle('visible', mode === 'domain');
}
function updateDns(value) {
  document.getElementById('dns-name').textContent = value || 'n8n.vasestranka.cz';
}

function selectUpdate(type) {
  currentUpdate = type;
  ['none','weekly','monthly'].forEach(function(t) {
    var opt = document.getElementById('opt-' + t);
    var rc  = document.getElementById('rc-' + t);
    if (opt) opt.classList.toggle('selected', t === type);
    if (rc)  rc.classList.toggle('selected', t === type);
  });
  document.getElementById('schedule-weekly').style.display  = type === 'weekly'  ? 'block' : 'none';
  document.getElementById('schedule-monthly').style.display = type === 'monthly' ? 'block' : 'none';
}

function goToPage1() {
  sessionStorage.removeItem('n8nPage');
  sessionStorage.removeItem('n8nHost');
  sessionStorage.removeItem('n8nEmail');
  showPage('page1');
}
function goToPage2() {
  var mode   = document.querySelector('input[name=mode]:checked').value;
  var domain = document.getElementById('domain').value.trim();
  var email  = document.getElementById('email').value.trim();
  if (mode === 'domain') {
    if (!domain) { alert('Zadejte doménu.'); return; }
    if (!email)  { alert('Zadejte e-mail pro Let\'s Encrypt.'); return; }
  }
  selectedHost  = mode === 'ip' ? 'SERVER_IP_PLACEHOLDER' : domain;
  selectedEmail = email;
  sessionStorage.setItem('n8nPage', '2');
  sessionStorage.setItem('n8nHost', selectedHost);
  sessionStorage.setItem('n8nEmail', selectedEmail);
  showPage('page2');
  selectUpdate('none');
}
function handleSubmit() {
  var schedule = '';
  if (currentUpdate === 'weekly') {
    schedule = document.getElementById('weekly-hour').value + ' * * ' + document.getElementById('weekly-day').value;
  } else if (currentUpdate === 'monthly') {
    schedule = document.getElementById('monthly-hour').value + ' ' + document.getElementById('monthly-day').value + ' * *';
  }
  var btn = document.getElementById('btn-install');
  var btnText = document.getElementById('btn-install-text');
  btnText.textContent = 'Spouštím instalaci...';
  btn.disabled = true;
  fetch('/submit', {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: 'host=' + encodeURIComponent(selectedHost)
        + '&email=' + encodeURIComponent(selectedEmail)
        + '&update=' + encodeURIComponent(currentUpdate)
        + '&schedule=' + encodeURIComponent(schedule)
  }).then(function(r) {
    if (r.ok) {
      document.getElementById('final-url').textContent = 'https://' + selectedHost;
      sessionStorage.setItem('n8nPage', '3');
      showPage('page3');
    } else {
      r.text().then(function(err) {
        btnText.textContent = 'Spustit instalaci';
        btn.disabled = false;
        if (err.indexOf('DNS_MISMATCH') === 0) {
          var resolved = err.split(':')[1];
          alert('Doména ' + selectedHost + ' směřuje na ' + resolved + ', ale IP tohoto serveru je SERVER_IP_PLACEHOLDER.\n\nZkontrolujte DNS záznam a zkuste znovu.');
          goToPage1();
        } else if (err === 'DNS_UNRESOLVED') {
          alert('Doménu ' + selectedHost + ' se nepodařilo přeložit.\n\nZkontrolujte DNS záznam. Změny DNS mohou trvat až 24 hodin.');
          goToPage1();
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
import http.server, ssl, urllib.parse, os, re, socket, base64, hmac, subprocess

SERVER_IP  = os.environ['SETUP_SERVER_IP']
SETUP_USER = os.environ['SETUP_USER']
PASS_HASH  = os.environ['SETUP_PASS_HASH']
HTML       = open('/tmp/setup.html').read()


def _extract_salt(hash_str: str) -> str:
    parts = hash_str.split('$')
    if len(parts) == 4:
        return parts[2]
    if len(parts) == 5 and parts[2].startswith('rounds='):
        return parts[3]
    return ''


def verify_password(username: str, password: str) -> bool:
    if not hmac.compare_digest(username, SETUP_USER):
        return False
    salt = _extract_salt(PASS_HASH)
    if not salt:
        return False
    try:
        result = subprocess.run(
            ['openssl', 'passwd', '-5', '-salt', salt, password],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            return False
        return hmac.compare_digest(result.stdout.strip(), PASS_HASH)
    except Exception:
        return False


class Handler(http.server.BaseHTTPRequestHandler):
    def check_auth(self) -> bool:
        auth_header = self.headers.get('Authorization', '')
        if not auth_header.startswith('Basic '):
            return False
        try:
            decoded = base64.b64decode(auth_header.split(' ', 1)[1]).decode('utf-8')
            username, password = decoded.split(':', 1)
            return verify_password(username, password)
        except Exception:
            return False

    def send_auth_request(self):
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="N8N Installation Setup"')
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.end_headers()
        self.wfile.write('Neautorizovaný přístup.'.encode('utf-8'))

    def _render_page(self) -> str:
        if not os.path.exists('/tmp/n8n_config'):
            return HTML
        host = 'server'
        try:
            with open('/tmp/n8n_config') as f:
                for line in f:
                    if line.startswith('N8N_HOST='):
                        host = line.split('=', 1)[1].strip()
        except Exception:
            pass
        # Stránka 3 (probíhá instalace) se renderuje přes JS na klientovi,
        # ale pokud někdo refreshne stránku po odeslání, zobrazíme static verzi
        done_html = HTML.replace(
            "document.getElementById('page1').classList.add('active');",
            ""
        )
        return re.sub(
            r"id=\"page1\" class=\"page active\"",
            'id="page1" class="page"',
            re.sub(
                r"id=\"page3\" class=\"page\"",
                'id="page3" class="page active"',
                done_html
            )
        ).replace('id="final-url"', 'id="final-url" style="color:var(--brand-primary);font-weight:600;"')

    def do_GET(self):
        if not self.check_auth():
            self.send_auth_request()
            return
        page = self._render_page()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(page.encode())

    def do_POST(self):
        if not self.check_auth():
            self.send_auth_request()
            return
        if self.path != '/submit':
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode()
        params = urllib.parse.parse_qs(body)
        host     = params.get('host',     [''])[0].strip()
        email    = params.get('email',    [''])[0].strip()
        update   = params.get('update',   ['none'])[0].strip()
        schedule = params.get('schedule', [''])[0].strip()
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
            f.write('N8N_HOST=' + host + '\n')
            f.write('N8N_EMAIL=' + email + '\n')
            f.write('N8N_UPDATE=' + update + '\n')
            f.write('N8N_UPDATE_SCHEDULE=' + schedule + '\n')
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

  # Uvolni port 443 pokud ho drží starý process z předchozího běhu
  OLD_PID=$(ss -tlnp 2>/dev/null | grep ':443 ' | grep -oP 'pid=\K[0-9]+' | head -1)
  if [[ -n "$OLD_PID" ]]; then
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
  fi

  SETUP_SERVER_IP="$DETECTED_IP" \
  SETUP_USER="$SETUP_USER" \
  SETUP_PASS_HASH="$SETUP_PASS_HASH" \
  python3 /tmp/n8n_setup_server.py &
  WEBSERVER_PID=$!

  info "Otevři v prohlížeči: https://$DETECTED_IP"
  info "Čekám na konfiguraci..."

  while [[ ! -f /tmp/n8n_config ]]; do
    sleep 2
  done

  source /tmp/n8n_config
  rm -f /tmp/n8n_setup_server.py /tmp/setup.html /tmp/setup.crt /tmp/setup.key
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
npm install -g n8n@latest
mkdir -p /opt/n8n/.n8n /opt/n8n/backup
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
ReadWritePaths=/opt/n8n/.n8n /opt/n8n/backup
ProtectHome=true
MemoryMax=85%
MemoryHigh=75%

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable n8n
log "systemd service vytvořena."

# ── Aktualizační skript ───────────────────────────────────────────────────────
info "Vytváření aktualizačního skriptu..."
cat > /usr/local/bin/n8n-update << 'UPDATEEOF'
#!/bin/bash
# n8n-update — bezpečná aktualizace na nejnovější stable verzi
# Průběh: záloha DB + dat → aktualizace npm → restart → ověření → smazání zálohy
# Při selhání: rollback ze zálohy, restart, log chyby

set -euo pipefail

LOG_FILE="/var/log/n8n-update.log"
BACKUP_DIR="/opt/n8n/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_BACKUP="$BACKUP_DIR/db_$TIMESTAMP.sql.gz"
DATA_BACKUP="$BACKUP_DIR/data_$TIMESTAMP.tar.gz"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# Načti DB přihlašovací údaje z n8n.env
DB_NAME=$(grep 'DB_POSTGRESDB_DATABASE=' /etc/n8n/n8n.env | cut -d'=' -f2)
DB_USER=$(grep 'DB_POSTGRESDB_USER='     /etc/n8n/n8n.env | cut -d'=' -f2)
DB_PASS=$(grep 'DB_POSTGRESDB_PASSWORD=' /etc/n8n/n8n.env | cut -d'=' -f2)

cleanup_backup() {
  rm -f "$DB_BACKUP" "$DATA_BACKUP"
  log "Záloha smazána."
}

rollback() {
  log "CHYBA: Spouštím rollback..."
  systemctl stop n8n 2>/dev/null || true

  # Obnova databáze
  if [[ -f "$DB_BACKUP" ]]; then
    log "Obnova databáze ze zálohy..."
    PGPASSWORD="$DB_PASS" sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME}_restore;" 2>/dev/null || true
    PGPASSWORD="$DB_PASS" sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME}_restore OWNER ${DB_USER};" 2>/dev/null || true
    zcat "$DB_BACKUP" | PGPASSWORD="$DB_PASS" sudo -u postgres psql "${DB_NAME}_restore" > /dev/null 2>&1 || true
    PGPASSWORD="$DB_PASS" sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
    PGPASSWORD="$DB_PASS" sudo -u postgres psql -c "ALTER DATABASE ${DB_NAME}_restore RENAME TO ${DB_NAME};" 2>/dev/null || true
    log "Databáze obnovena."
  fi

  # Obnova dat
  if [[ -f "$DATA_BACKUP" ]]; then
    log "Obnova dat ze zálohy..."
    rm -rf /opt/n8n/.n8n
    tar -xzf "$DATA_BACKUP" -C /opt/n8n/ 2>/dev/null || true
    chown -R n8n:n8n /opt/n8n/.n8n
    log "Data obnovena."
  fi

  systemctl start n8n 2>/dev/null || true
  log "Rollback dokončen. n8n spuštěn s předchozí verzí."
}

log "=== Spouštím aktualizaci n8n ==="
OLD_VERSION=$(sudo -u n8n /usr/local/bin/n8n --version 2>/dev/null || echo "neznámá")
log "Aktuální verze: $OLD_VERSION"

# 1. Záloha databáze
log "Zálohuji databázi..."
mkdir -p "$BACKUP_DIR"
PGPASSWORD="$DB_PASS" sudo -u postgres pg_dump "$DB_NAME" | gzip > "$DB_BACKUP"
log "Záloha DB: $DB_BACKUP"

# 2. Záloha dat (credentials, settings)
log "Zálohuji /opt/n8n/.n8n ..."
tar -czf "$DATA_BACKUP" -C /opt/n8n .n8n 2>/dev/null
log "Záloha dat: $DATA_BACKUP"

# 3. Aktualizace npm balíčku
log "Aktualizuji n8n na nejnovější stable verzi..."
if ! npm install -g n8n@latest >> "$LOG_FILE" 2>&1; then
  log "CHYBA: npm install selhal."
  rollback
  exit 1
fi

NEW_VERSION=$(sudo -u n8n /usr/local/bin/n8n --version 2>/dev/null || echo "neznámá")
log "Nová verze: $NEW_VERSION"

# 4. Restart service
log "Restartuji n8n service..."
systemctl restart n8n

# 5. Ověření že service nastartovala (čekáme max 30s)
TRIES=0
while ! systemctl is-active --quiet n8n; do
  sleep 3
  TRIES=$((TRIES + 1))
  if [[ $TRIES -ge 10 ]]; then
    log "CHYBA: n8n se nespustil po aktualizaci. Spouštím rollback..."
    rollback
    exit 1
  fi
done

log "n8n úspěšně spuštěn po aktualizaci ($OLD_VERSION → $NEW_VERSION)."

# 6. Smazání zálohy po úspěšné aktualizaci
cleanup_backup
log "=== Aktualizace dokončena ==="
UPDATEEOF

chmod +x /usr/local/bin/n8n-update
log "Aktualizační skript vytvořen: /usr/local/bin/n8n-update"

# ── Nastavení cronu (pokud uživatel zvolil automatické aktualizace) ───────────
N8N_UPDATE="${N8N_UPDATE:-none}"
N8N_UPDATE_SCHEDULE="${N8N_UPDATE_SCHEDULE:-}"

if [[ "$N8N_UPDATE" != "none" && -n "$N8N_UPDATE_SCHEDULE" ]]; then
  info "Nastavuji cron pro automatické aktualizace ($N8N_UPDATE)..."

  # Formát N8N_UPDATE_SCHEDULE:
  #   týdenní:  "HOUR * * DOW"   → cron: "0 HOUR * * DOW"
  #   měsíční:  "HOUR DOM * *"   → cron: "0 HOUR DOM * *"
  CRON_EXPR="0 $N8N_UPDATE_SCHEDULE"
  CRON_LINE="$CRON_EXPR root /usr/local/bin/n8n-update >> /var/log/n8n-update.log 2>&1"

  echo "$CRON_LINE" > /etc/cron.d/n8n-update
  chmod 644 /etc/cron.d/n8n-update

  log "Cron nastaven: $CRON_EXPR"
  log "Soubor: /etc/cron.d/n8n-update"
else
  info "Automatické aktualizace vypnuty — cron nevytvořen."
fi

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
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
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
    listen 80 default_server;
    server_name _;
    return 301 https://${N8N_HOST}\$request_uri;
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

  cat >> /etc/nginx/sites-available/n8n <<EOF

server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/letsencrypt/live/${N8N_HOST}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${N8N_HOST}/privkey.pem;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
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
echo "  URL:         https://${N8N_HOST}"
if [[ "$N8N_UPDATE" != "none" ]]; then
echo "  Aktualizace: automaticky ($N8N_UPDATE) — cron: /etc/cron.d/n8n-update"
else
echo "  Aktualizace: ruční — spusť: n8n-update"
fi
echo ""
echo "  Logy n8n:    journalctl -u n8n -f"
echo "  Logy update: tail -f /var/log/n8n-update.log"
echo "  Konfig:      /etc/n8n/n8n.env  (root only)"
echo ""

rm -f /tmp/n8n_config /tmp/setup.crt /tmp/setup.key /tmp/setup.html \
      /tmp/n8n_setup_server.py

apt-get autoremove -y -q
apt-get autoclean -y -q
apt-get clean -q
rm -rf /var/lib/apt/lists/*

SCRIPT_PATH="$(readlink -f "$0")"
(sleep 2 && rm -f "$SCRIPT_PATH") &>/dev/null &