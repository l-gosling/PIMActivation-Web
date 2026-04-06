# PIM Activation Web

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Docker](https://img.shields.io/badge/Docker-Container-blue?style=flat-square)
![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-blue?style=flat-square)
![Pode](https://img.shields.io/badge/Pode-2.12-purple?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Docker-lightgrey?style=flat-square)

A web-based Privileged Identity Management (PIM) tool for Microsoft Entra ID, PIM-enabled groups, and Azure Resources. Built with Pode (PowerShell HTTP server) running in Docker, with Entra ID OAuth 2.0 authentication.

## Key Features

- **Web-Based UI** - No client installation required, accessible from any browser
- **Entra ID Roles** - View and activate/deactivate Entra ID directory roles with AU scope support
- **PIM Groups** - Manage PIM-enabled security group memberships (member/owner)
- **Azure Resources** - Activate/deactivate Azure subscription and resource roles via PIM
- **Saved Profiles** - Save frequently used role combinations and activate them with two clicks
- **Activation History** - Built-in history log with analytics (success rate, most activated roles, activity by day)
- **Entra Audit Logs** - Background sync of PIM events from Entra audit logs (last 30 days)
- **Progress Bar** - Visual progress for batch activations/deactivations with per-role policy enforcement
- **Policy Enforcement** - Automatic duration capping when a role's policy max is lower than the selected duration
- **OAuth 2.0** - Secure authentication via Entra ID with automatic token refresh
- **HTTPS** - TLS support with custom certificates
- **Dark/Light Theme** - Auto, light, or dark mode with full color customization
- **Security Headers** - HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy
- **SameSite Cookies** - CSRF protection via SameSite=Lax on all session cookies

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
docker compose up -d --build
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
| `User.Read` | Microsoft Graph | Delegated | No | Read signed-in user's display name, email, and object ID |
| `openid` | Microsoft Graph | Delegated | No | OpenID Connect sign-in (provides `id_token`) |
| `profile` | Microsoft Graph | Delegated | No | Access user profile claims (name, preferred_username) |
| `email` | Microsoft Graph | Delegated | No | Access user email address |
| `offline_access` | Microsoft Graph | Delegated | No | Obtain refresh token for silent token renewal |
| `RoleManagement.ReadWrite.Directory` | Microsoft Graph | Delegated | Yes | List and activate/deactivate Entra ID directory roles |
| `PrivilegedAccess.ReadWrite.AzureADGroup` | Microsoft Graph | Delegated | Yes | List and activate/deactivate PIM-enabled group memberships |
| `Policy.Read.All` | Microsoft Graph | Delegated | Yes | Read role policies (max duration, MFA, justification, ticket, approval) |
| `AdministrativeUnit.Read.All` | Microsoft Graph | Delegated | Yes | Resolve Administrative Unit IDs to display names |
| `AuditLog.Read.All` | Microsoft Graph | Delegated | Yes | Read Entra audit logs for activation history sync |

#### Optional (for Azure Resource Roles)

| Permission | API | Type | Admin Consent | Purpose |
|-----------|-----|------|---------------|---------|
| `user_impersonation` | Azure Service Management | Delegated | No | List and activate/deactivate Azure PIM roles across subscriptions |

> **Note:** `user_impersonation` on Azure Service Management does not require admin consent and does not grant elevated access. Enable `INCLUDE_AZURE_RESOURCES=true` in `.env` to use this feature.

## Docker Architecture

```
docker-compose.yml
  |
  +-- pim-app (container)
       |-- Pode HTTP/HTTPS server (port 8080)
       |-- PowerShell 7 + .NET SDK 8.0 Alpine
       |-- Invoke-WebRequest for all API calls
       |
       DNS: 8.8.8.8, 8.8.4.4 (Google DNS for reliable IPv4 resolution)
       |
       Volumes:
       |-- ./certs:/etc/pim-certs:ro     (TLS certificates)
       |-- ./config:/etc/pim-config:ro   (config files)
       |-- pim-data:/var/pim-data        (persistent preferences, profiles, history)
       |-- ./logs:/var/log/pim:rw        (log files)
       |
       Ports:
       |-- 443 -> 8080 (HTTPS, configurable via HTTPS_PORT)
```

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

## Project Structure

```
PIMActivation/
|-- Dockerfile                          # Container build (Alpine Linux)
|-- docker-compose.yml                  # Service orchestration + DNS config
|-- .env.example                        # Environment template
|-- architecture.md                     # System architecture & ADRs
|-- pode-onboarding.md                  # Pode framework onboarding guide
|-- CERTIFICATES.md                     # HTTPS certificate guide
|-- certs/                              # TLS certificates (mounted)
|-- config/                             # Config files (mounted)
|-- logs/                               # Log output (mounted)
|-- src/pode-app/
    |-- pim-server.ps1                  # Pode server entry point
    |-- middleware/
    |   +-- AuthMiddleware.ps1          # OAuth 2.0, sessions, SameSite cookies
    |-- modules/
    |   |-- Configuration.ps1           # Environment config reader
    |   |-- Logger.ps1                  # Structured JSON logging
    |   +-- PIMApiLayer.ps1             # Graph & Azure API (Invoke-WebRequest)
    |-- routes/
    |   |-- Config.ps1                  # Theme, features, preferences, profiles
    |   +-- Roles.ps1                   # Role CRUD API + Entra audit history
    +-- public/
        |-- index.html                  # Single-page UI
        |-- css/style.css               # Fluent Design CSS (light + dark)
        |-- images/                     # Logo, favicon
        +-- js/
            |-- api-client.js           # HTTP client (cookie-based auth)
            |-- app.js                  # App init, toast, progress bar, theme
            |-- auth.js                 # OAuth flow UI
            |-- roles.js                # Role tables, selection, deactivation
            |-- activation.js           # Activation dialog, batch activation
            |-- profiles.js             # Saved role profiles
            +-- history.js              # Activation history & analytics
```

## Security

- **OAuth 2.0 Authorization Code** flow with Entra ID
- **HttpOnly + Secure + SameSite=Lax** session cookies (via custom `Set-SecureCookie` for Pode 2.x compatibility)
- **Security headers middleware** — HSTS, X-Frame-Options (DENY), X-Content-Type-Options (nosniff), Referrer-Policy, Permissions-Policy
- **Automatic token refresh** using refresh tokens with single-retry on 401
- **Cryptographic session IDs** (48-byte random, Base64url-safe)
- **Session expiry enforcement** — checked on every protected request, not just timer
- **Duration validation** — activation duration validated server-side (1-1440 minutes)
- **Input validation** — role IDs validated as GUIDs
- **File permissions** — preference storage directory at 700 (owner-only)
- **No tokens in process args** — uses `Invoke-WebRequest` (native PowerShell) instead of curl
- **No temp files** — request bodies passed directly, never written to disk

## Troubleshooting

### Container won't start

```bash
docker compose logs --tail=30
```

### Session expired errors

The Graph access token auto-refreshes via the refresh token. If refresh fails, sign out and sign back in.

### Azure roles not showing

1. Ensure `INCLUDE_AZURE_RESOURCES=true` in `.env`
2. Add `user_impersonation` permission on Azure Service Management in your app registration
3. Check user preference: Settings > "Show Azure Resource roles"
4. Sign out and back in to get a new Azure Management token

### Audit history not loading

1. Ensure `AuditLog.Read.All` permission is granted with admin consent
2. Sign out and back in to get a token with the new scope
3. Audit logs load in the background — check browser console for errors

### HTTPS certificate issues

```bash
# Verify cert and key match
openssl x509 -noout -modulus -in certs/cert.pem | openssl md5
openssl rsa -noout -modulus -in certs/key.pem | openssl md5
```

Both MD5 values must match. See [CERTIFICATES.md](CERTIFICATES.md) for more.

## Documentation

- [Architecture & Decisions](architecture.md) — system design, module dependencies, ADRs, Mermaid diagrams
- [Pode Onboarding](pode-onboarding.md) — Pode framework concepts mapped to standard PowerShell
- [HTTPS Certificates](CERTIFICATES.md) — TLS setup guide
- [Pode Framework](https://badgerati.github.io/Pode/) — official Pode documentation
- [Microsoft Graph PIM API](https://learn.microsoft.com/en-us/graph/api/resources/privilegedidentitymanagementv3-overview)

## License

[MIT](LICENSE)
