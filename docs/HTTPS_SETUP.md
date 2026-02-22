# HTTPS Setup Guide

BetterDesk Console supports native HTTPS with TLS certificates, as well as reverse proxy configurations with Caddy or Nginx.

## Quick Start

### Option 1: Native HTTPS (Self-Signed Certificate)

Generate a self-signed certificate for testing:

```bash
# Linux
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/rustdesk/ssl/privkey.pem \
  -out /opt/rustdesk/ssl/fullchain.pem \
  -subj "/CN=betterdesk.local"
```

```powershell
# Windows (PowerShell)
$cert = New-SelfSignedCertificate -DnsName "betterdesk.local" -CertStoreLocation "cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(1)
Export-PfxCertificate -Cert $cert -FilePath C:\RustDesk\ssl\cert.pfx -Password (ConvertTo-SecureString -String "password" -Force -AsPlainText)
# Convert to PEM with OpenSSL or use .pfx directly
```

Then edit your `.env` file:

```env
HTTPS_ENABLED=true
HTTPS_PORT=5443
SSL_CERT_PATH=/opt/rustdesk/ssl/fullchain.pem
SSL_KEY_PATH=/opt/rustdesk/ssl/privkey.pem
HTTP_REDIRECT_HTTPS=true
```

Restart the console service and access it at `https://your-server:5443`.

### Option 2: Let's Encrypt (Production)

Using [Certbot](https://certbot.eff.org/):

```bash
# Install certbot
sudo apt install certbot

# Get certificate (standalone mode - stop BetterDesk console first)
sudo systemctl stop betterdesk-console
sudo certbot certonly --standalone -d console.yourdomain.com
sudo systemctl start betterdesk-console
```

Update `.env`:

```env
HTTPS_ENABLED=true
HTTPS_PORT=443
SSL_CERT_PATH=/etc/letsencrypt/live/console.yourdomain.com/fullchain.pem
SSL_KEY_PATH=/etc/letsencrypt/live/console.yourdomain.com/privkey.pem
SSL_CA_PATH=/etc/letsencrypt/live/console.yourdomain.com/chain.pem
HTTP_REDIRECT_HTTPS=true
```

Set up auto-renewal:

```bash
# Add to crontab
0 0 1 * * certbot renew --pre-hook "systemctl stop betterdesk-console" --post-hook "systemctl start betterdesk-console"
```

### Option 3: Reverse Proxy with Caddy (Recommended for Production)

[Caddy](https://caddyserver.com/) automatically provisions and renews HTTPS certificates.

```bash
# Install Caddy
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install caddy
```

Create `/etc/caddy/Caddyfile`:

```caddy
console.yourdomain.com {
    reverse_proxy localhost:5000

    # Optional: compress responses
    encode gzip zstd

    # Security headers (Caddy adds HSTS by default)
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
    }
}
```

```bash
sudo systemctl enable caddy
sudo systemctl start caddy
```

With Caddy, leave `HTTPS_ENABLED=false` in `.env` since Caddy handles TLS termination.

### Option 4: Reverse Proxy with Nginx

Install Nginx and Certbot:

```bash
sudo apt install nginx certbot python3-certbot-nginx
```

Create `/etc/nginx/sites-available/betterdesk`:

```nginx
server {
    listen 80;
    server_name console.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support (for future remote desktop client)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/betterdesk /etc/nginx/sites-enabled/
sudo certbot --nginx -d console.yourdomain.com
sudo systemctl restart nginx
```

With Nginx reverse proxy, leave `HTTPS_ENABLED=false` in `.env`.

---

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `HTTPS_ENABLED` | `false` | Enable native HTTPS server |
| `HTTPS_PORT` | `5443` | HTTPS listening port |
| `SSL_CERT_PATH` | *(empty)* | Path to SSL certificate (PEM format) |
| `SSL_KEY_PATH` | *(empty)* | Path to SSL private key (PEM format) |
| `SSL_CA_PATH` | *(empty)* | Path to CA bundle / chain (optional) |
| `HTTP_REDIRECT_HTTPS` | `true` | Redirect HTTP traffic to HTTPS when HTTPS is enabled |

## Security Notes

When HTTPS is enabled, BetterDesk Console automatically:

- Enables **HSTS** (Strict-Transport-Security) header with 1 year max-age
- Sets `Secure` flag on session cookies
- Enables `upgrade-insecure-requests` CSP directive
- Enables Cross-Origin-Opener-Policy `same-origin`
- Allows `wss://` in Content-Security-Policy for future WebSocket connections

When HTTPS is **not** enabled (default), these stricter policies are disabled to avoid breaking HTTP-only deployments on internal networks.

## Firewall Rules

If you enable native HTTPS, make sure to open the HTTPS port:

```bash
# Linux (ufw)
sudo ufw allow 5443/tcp

# Linux (firewalld)
sudo firewall-cmd --permanent --add-port=5443/tcp
sudo firewall-cmd --reload
```

```powershell
# Windows
New-NetFirewallRule -DisplayName "BetterDesk HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5443 -Action Allow
```

## Troubleshooting

### "HTTPS enabled but certificates not found/invalid"

The server will log this warning and fall back to HTTP mode. Check:
1. Certificate file paths in `.env` are correct
2. Files are readable by the BetterDesk process (check permissions)
3. Certificate format is PEM (not DER or PFX)

### Certificate Permission Errors

Let's Encrypt certificates are often readable only by root:

```bash
# Allow BetterDesk to read certificates
sudo chmod 644 /etc/letsencrypt/live/console.yourdomain.com/fullchain.pem
sudo chmod 640 /etc/letsencrypt/live/console.yourdomain.com/privkey.pem
sudo chgrp root /etc/letsencrypt/live/console.yourdomain.com/privkey.pem
```

### Mixed Content Warnings

If you access the console via HTTPS but see mixed content warnings, ensure `HTTPS_ENABLED=true` is set so the security middleware enables `upgrade-insecure-requests`.

### Behind a Reverse Proxy

When using a reverse proxy (Caddy/Nginx), keep `HTTPS_ENABLED=false` and let the proxy handle TLS. The proxy should set `X-Forwarded-Proto: https` so the application knows the original protocol. Express trusts proxy headers when configured—this is handled automatically.
