# PIM Activation Web

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Docker](https://img.shields.io/badge/Docker-Container-blue?style=flat-square)
![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-blue?style=flat-square)
![Pode](https://img.shields.io/badge/Pode-2.12-purple?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Docker-lightgrey?style=flat-square)

A web-based Privileged Identity Management (PIM) tool for Microsoft Entra ID, PIM-enabled groups, and Azure Resources. Built with Pode (PowerShell HTTP server) running in Docker, with Entra ID OAuth 2.0 authentication.

> This is the web-based successor to the [PIMActivation PowerShell Module](https://github.com/l-gosling/PIMActivation) (Windows Forms GUI).

## Key Features

- **Web-Based UI** - No client installation required, accessible from any browser
- **Entra ID Roles** - View and activate/deactivate Entra ID directory roles with AU scope support
- **PIM Groups** - Manage PIM-enabled security group memberships (member/owner)
- **Azure Resources** - Activate/deactivate Azure subscription and resource roles via PIM
- **OAuth 2.0** - Secure authentication via Entra ID with automatic token refresh
- **HTTPS** - TLS support with custom certificates
- **Dark/Light Theme** - Auto, light, or dark mode with full color customization via environment variables
- **Persistent Preferences** - Per-user settings stored on Docker volume
- **Policy Compliance** - Shows MFA, justification, ticket, and approval requirements per role
- **Customizable** - Branding (logo, colors, copyright) configurable via `.env` file

## Screenshots

*Table-based layout showing Active Roles and Eligible Roles with type badges, scope, member type, policy requirements, and expiration times.*

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/l-gosling/PIMActivation-Web.git
cd PIMActivation-Web
```

### 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` with your Entra ID app registration details:

```env
ENTRA_TENANT_ID=your-tenant-id.onmicrosoft.com
ENTRA_CLIENT_ID=your-app-client-id
ENTRA_CLIENT_SECRET=your-app-client-secret
ENTRA_REDIRECT_URI=https://localhost/api/auth/callback
```

### 3. Set Up HTTPS Certificate

```bash
mkdir -p certs
openssl req -x509 -newkey rsa:4096 -keyout certs/key.pem -out certs/cert.pem -days 365 -nodes -subj "/CN=localhost"
```

See [CERTIFICATES.md](CERTIFICATES.md) for production certificate options (Let's Encrypt, enterprise CA, PFX).

### 4. Start the Container

```bash
docker-compose up -d --build
```

### 5. Access the UI

Open **https://localhost** in your browser. You will be automatically redirected to Entra ID for authentication.

## Entra ID App Registration

### Create the App

1. Go to **Azure Portal** > **App registrations** > **New registration**
2. Name: `PIM Activation Web` (or your choice)
3. Supported account types: **Single tenant**
4. Redirect URI: **Web** > `https://localhost/api/auth/callback`

### Configure Authentication

1. Go to **Authentication**
2. Add redirect URI: `https://localhost/api/auth/callback`
3. Enable **ID tokens** under Implicit grant

### Add Client Secret

1. Go to **Certificates & secrets** > **New client secret**
2. Copy the secret value to your `.env` file as `ENTRA_CLIENT_SECRET`

### API Permissions (Delegated)

Add the following **delegated** permissions and grant admin consent:

#### Required

| Permission | API | Type | Admin Consent | Purpose |
|-----------|-----|------|---------------|---------|
| `User.Read` | Microsoft Graph | Delegated | No | Read user profile |
| `openid` | Microsoft Graph | Delegated | No | OpenID Connect sign-in |
| `profile` | Microsoft Graph | Delegated | No | User profile claims |
| `email` | Microsoft Graph | Delegated | No | User email claim |
| `offline_access` | Microsoft Graph | Delegated | No | Refresh tokens |
| `RoleManagement.ReadWrite.Directory` | Microsoft Graph | Delegated | Yes | Activate/deactivate Entra roles |
| `PrivilegedAccess.ReadWrite.AzureADGroup` | Microsoft Graph | Delegated | Yes | Activate/deactivate PIM groups |
| `Policy.Read.All` | Microsoft Graph | Delegated | Yes | Read role policies (MFA, justification) |
| `AdministrativeUnit.Read.All` | Microsoft Graph | Delegated | Yes | Resolve AU scope names |

#### Optional (for Azure Resource Roles)

| Permission | API | Type | Admin Consent | Purpose |
|-----------|-----|------|---------------|---------|
| `user_impersonation` | Azure Service Management | Delegated | No | Azure PIM role management |

> **Note:** `user_impersonation` on Azure Service Management is low-risk and does not require admin consent. It only allows the app to act as the user within their existing Azure RBAC permissions.

## Docker Architecture

```
docker-compose.yml
  |
  +-- pim-app (container)
       |-- Pode HTTP/HTTPS server (port 8080)
       |-- PowerShell 7 + .NET SDK Alpine
       |-- curl (for Graph/Azure REST API calls)
       |
       Volumes:
       |-- ./certs:/etc/pim-certs:ro     (TLS certificates)
       |-- ./config:/etc/pim-config:ro   (config files)
       |-- pim-data:/var/pim-data        (persistent preferences)
       |-- ./logs:/var/log/pim:rw        (log files)
       |
       Ports:
       |-- 443 -> 8080 (HTTPS, configurable via HTTPS_PORT)
```

### Container Base Image

`mcr.microsoft.com/dotnet/sdk:8.0-alpine` — includes PowerShell 7 and .NET runtime. The Pode module is installed during build.

## Configuration Reference

All configuration is done via the `.env` file. The container reads these at startup.

### Authentication

| Variable | Default | Description |
|----------|---------|-------------|
| `ENTRA_TENANT_ID` | *required* | Your Entra ID tenant ID |
| `ENTRA_CLIENT_ID` | *required* | App registration client ID |
| `ENTRA_CLIENT_SECRET` | *required* | App registration client secret |
| `ENTRA_REDIRECT_URI` | `https://localhost/api/auth/callback` | OAuth redirect URI |

### Server

| Variable | Default | Description |
|----------|---------|-------------|
| `HTTPS_PORT` | `443` | Host port for HTTPS |
| `PODE_PORT` | `8080` | Internal container port |
| `PODE_MODE` | `production` | Server mode (`production` or `development`) |
| `LOG_LEVEL` | `Information` | Log level (`Verbose`, `Debug`, `Information`, `Warning`, `Error`) |
| `SESSION_TIMEOUT` | `3600` | Session duration in seconds |

### Feature Flags

| Variable | Default | Description |
|----------|---------|-------------|
| `INCLUDE_ENTRA_ROLES` | `true` | Enable Entra ID directory roles |
| `INCLUDE_GROUPS` | `true` | Enable PIM-enabled groups |
| `INCLUDE_AZURE_RESOURCES` | `false` | Enable Azure resource roles (requires `user_impersonation` permission) |

### Theme & Branding

| Variable | Default | Description |
|----------|---------|-------------|
| `THEME_PRIMARY_COLOR` | `#0078D4` | Primary brand color |
| `THEME_SECONDARY_COLOR` | `#107C10` | Secondary color |
| `THEME_DANGER_COLOR` | `#DA3B01` | Error/danger color |
| `THEME_WARNING_COLOR` | `#FFB900` | Warning color |
| `THEME_SUCCESS_COLOR` | `#107C10` | Success color |
| `THEME_SECTION_HEADER_COLOR` | *(primary)* | Table section header background |
| `THEME_ENTRA_COLOR` | `#0078D4` | Entra type badge color |
| `THEME_GROUP_COLOR` | `#107C10` | Group type badge color |
| `THEME_AZURE_COLOR` | `#003067` | Azure type badge color |
| `THEME_FONT_FAMILY` | `Segoe UI, -apple-system, sans-serif` | Font family |
| `APP_COPYRIGHT` | *(empty)* | Footer copyright text (hidden when empty) |

## HTTPS Certificates

Certificates are mounted from the host `./certs/` directory:

```
certs/
  cert.pem    # Certificate chain (PEM)
  key.pem     # Private key (PEM, no passphrase)
```

| Method | Command |
|--------|---------|
| **Self-signed** (dev) | `openssl req -x509 -newkey rsa:4096 -keyout certs/key.pem -out certs/cert.pem -days 365 -nodes -subj "/CN=localhost"` |
| **Let's Encrypt** | Copy `fullchain.pem` and `privkey.pem` from certbot |
| **Enterprise PFX** | `openssl pkcs12 -in cert.pfx -clcerts -nokeys -out certs/cert.pem` and `openssl pkcs12 -in cert.pfx -nocerts -nodes -out certs/key.pem` |

If no certificates are found, the server falls back to HTTP automatically.

See [CERTIFICATES.md](CERTIFICATES.md) for detailed instructions.

## Project Structure

```
PIMActivation-Web/
|-- Dockerfile                          # Container build
|-- docker-compose.yml                  # Service orchestration
|-- .env.example                        # Environment template
|-- CERTIFICATES.md                     # HTTPS certificate guide
|-- certs/                              # TLS certificates (mounted)
|-- config/                             # Config files (mounted)
|-- logs/                               # Log output (mounted)
|-- src/pode-app/
    |-- pim-server.ps1                  # Pode server entry point
    |-- middleware/
    |   +-- AuthMiddleware.ps1          # OAuth 2.0 flow, session management
    |-- modules/
    |   |-- Configuration.ps1           # Environment config reader
    |   |-- Logger.ps1                  # Structured logging
    |   +-- PIMApiLayer.ps1             # Graph & Azure REST API calls
    |-- routes/
    |   |-- Config.ps1                  # Theme, features, preferences API
    |   +-- Roles.ps1                   # Role CRUD API
    +-- public/
        |-- index.html                  # Single-page UI
        |-- css/style.css               # Fluent Design CSS
        |-- images/                     # Logo, favicon
        +-- js/
            |-- api-client.js           # HTTP client
            |-- app.js                  # Theme, init
            |-- auth.js                 # OAuth flow
            |-- activation.js           # Activation dialog
            +-- roles.js                # Role tables
```

## Security

- **OAuth 2.0 Authorization Code** flow with Entra ID
- **HttpOnly + Secure** session cookies with SameSite
- **Automatic token refresh** using refresh tokens
- **Cryptographic session IDs** (48-byte random)
- **Session cleanup timer** purges expired sessions every 5 minutes
- **Input validation** — role IDs validated as GUIDs
- **Auth checks** on all protected API endpoints
- **Generic error messages** to client, detailed errors logged server-side
- **No secrets in logs** — tokens and OAuth details stripped from output
- **HTTPS** with custom certificate support

## Troubleshooting

### Container won't start

```bash
docker-compose logs --tail=30
```

### Session expired errors

The Graph access token auto-refreshes via the refresh token. If refresh fails, sign out and sign back in.

### Azure roles not showing

1. Ensure `INCLUDE_AZURE_RESOURCES=true` in `.env`
2. Add `user_impersonation` permission on Azure Service Management in your app registration
3. Check user preference: Settings > "Show Azure Resource roles"
4. Sign out and back in to get a new Azure Management token

### Roles not loading

Check the container logs for Graph API errors:

```bash
docker-compose logs --tail=50 | grep -i "error\|failed"
```

### HTTPS certificate issues

```bash
# Verify cert and key match
openssl x509 -noout -modulus -in certs/cert.pem | openssl md5
openssl rsa -noout -modulus -in certs/key.pem | openssl md5
```

Both MD5 values must match. See [CERTIFICATES.md](CERTIFICATES.md) for more.

## Related

- [PIMActivation PowerShell Module](https://github.com/l-gosling/PIMActivation) - Original Windows Forms GUI version
- [Pode](https://badgerati.github.io/Pode/) - PowerShell cross-platform web server
- [Microsoft Graph PIM API](https://learn.microsoft.com/en-us/graph/api/resources/privilegedidentitymanagementv3-overview)

## License

[MIT](LICENSE)
