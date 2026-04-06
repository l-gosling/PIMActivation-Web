# HTTPS Certificate Setup

PIM Activation Web supports HTTPS. Certificates are mounted from the host `./certs/` directory into the container.

## Certificate Files

Place your certificate files in the `./certs/` directory:

```
certs/
  cert.pem    # Certificate (PEM format)
  key.pem     # Private key (PEM format, unencrypted)
```

The container expects:
- `cert.pem` — the full certificate chain (server cert + intermediates)
- `key.pem` — the private key in PEM format **without a passphrase**

## Option 1: Self-Signed Certificate (Development)

Generate a self-signed certificate for local development:

```bash
openssl req -x509 -newkey rsa:4096 -keyout certs/key.pem -out certs/cert.pem -days 365 -nodes -subj "/CN=localhost"
```

Your browser will show a security warning — this is expected for self-signed certs.

## Option 2: Let's Encrypt / ACME (Production)

If you have a domain name, use certbot or any ACME client:

```bash
# Example with certbot (run on the host)
certbot certonly --standalone -d pim.yourdomain.com

# Copy the generated files
cp /etc/letsencrypt/live/pim.yourdomain.com/fullchain.pem certs/cert.pem
cp /etc/letsencrypt/live/pim.yourdomain.com/privkey.pem certs/key.pem
```

## Option 3: Enterprise CA / PFX Certificate

If you have a `.pfx` file from your enterprise CA:

```bash
# Extract certificate
openssl pkcs12 -in certificate.pfx -clcerts -nokeys -out certs/cert.pem

# Extract private key (remove passphrase)
openssl pkcs12 -in certificate.pfx -nocerts -nodes -out certs/key.pem
```

If you have separate `.crt` and `.key` files, just rename/copy them:

```bash
cp your-certificate.crt certs/cert.pem
cp your-private-key.key certs/key.pem
```

## Configuration

Update your `.env` file:

```env
# Redirect URI must use https
ENTRA_REDIRECT_URI=https://your-hostname/api/auth/callback

# Host port (default 443)
HTTPS_PORT=443
```

Update your Entra ID app registration:
- Change the redirect URI to `https://your-hostname/api/auth/callback`

## Restart

After placing certificates, restart the container:

```bash
docker-compose down && docker-compose up -d --build
```

Check the logs to verify HTTPS is active:

```bash
docker-compose logs | grep -i "https\|endpoint"
```

You should see: `HTTPS endpoint configured on port 8080`

## Fallback

If no certificate files are found in `./certs/`, the server automatically falls back to HTTP.

## Troubleshooting

**"key values mismatch"** — the cert and key don't match. Verify with:
```bash
openssl x509 -noout -modulus -in certs/cert.pem | openssl md5
openssl rsa -noout -modulus -in certs/key.pem | openssl md5
```
Both MD5 values must match.

**"unable to load private key"** — the key has a passphrase. Remove it:
```bash
openssl rsa -in certs/key.pem -out certs/key-nopass.pem
mv certs/key-nopass.pem certs/key.pem
```
