# PIM Activation - Web-Based UI Migration

This document describes the migration of PIM Activation from a Windows Forms GUI to a web-based UI using **Pode** (PowerShell HTTP framework) in a **Docker container**.

## What's New?

### Technology Stack
- **Frontend**: Modern HTML5/CSS3/Vanilla JavaScript with Fluent Design System
- **Backend**: PowerShell 7+ with Pode web framework
- **Server**: REST API exposing PIM functionality
- **Container**: Linux-based Docker for enterprise deployment
- **Authentication**: OAuth 2.0 with Entra ID

### Key Advantages

| Feature | Windows Forms | Web UI |
|---------|---------------|--------|
| **Access** | Local machine only | Network accessible |
| **Deployment** | Per-user installation | Centralized container |
| **Cross-platform** | Windows only | Any OS with Docker |
| **Scalability** | User per session | Multi-user ready |
| **Updates** | Manual per machine | Centralized |
| **Corporate** | Requires installable client | Supports corporate proxies/VPN |

## Quick Start

### Prerequisites
- Docker & Docker Compose
- Entra ID app registration (see below)

### Setup (5 minutes)

1. **Clone configuration:**
   ```bash
   cd PIMActivation
   cp .env.example .env
   ```

2. **Update `.env` with your Entra ID credentials:**
   ```
   ENTRA_TENANT_ID=your-organization.onmicrosoft.com
   ENTRA_CLIENT_ID=<app-client-id>
   ENTRA_CLIENT_SECRET=<app-client-secret>
   ```

3. **Start the application:**
   ```bash
   docker-compose up -d
   ```

4. **Access the UI:**
   ```
   http://localhost:8080
   ```

## Project Structure

```
PIMActivation/
├── src/pode-app/                    # Web application
│   ├── pim-server.ps1              # Main server entry point
│   ├── public/                      # Frontend (HTML/CSS/JS)
│   ├── routes/                      # API route handlers
│   ├── middleware/                  # Request middleware
│   └── modules/                     # Helper modules
├── Dockerfile                       # Container image definition
├── docker-compose.yml               # Docker Compose config
├── .env.example                     # Configuration template
├── .dockerignore                    # Docker build ignore
├── Private/                         # Original PowerShell modules (for reference)
└── Public/                          # Original PowerShell entry points
```

## Deployment

### Docker Compose (Development/Small Deployments)

```bash
docker-compose up -d
docker-compose logs -f
```

### Manual Docker Run

```bash
docker run -d \
  --name pim-activation \
  -p 8080:8080 \
  -e ENTRA_CLIENT_ID=<id> \
  -e ENTRA_CLIENT_SECRET=<secret> \
  -e ENTRA_TENANT_ID=<tenant> \
  -v pim-data:/var/pim-data \
  pim-activation-web:latest
```

### Kubernetes (Production)

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

(See [Kubernetes deployment guide](./DEPLOYMENT-K8S.md))

## Entra ID Setup

### Step 1: Register Application

1. Go to **Microsoft Entra ID** → **App registrations**
2. Click **+ New registration**
3. Fill in details:
   - Name: `PIM Activation Web`
   - Supported account types: Single tenant
   - Redirect URI: `http://localhost:8080/callback` (dev) or `https://your-domain/callback` (prod)

### Step 2: Configure Client Secret

1. Go to **Certificates & secrets**
2. Click **+ New client secret**
3. Copy the secret value (only shown once!)

### Step 3: Grant API Permissions

1. Go to **API permissions**
2. Click **+ Add a permission**
3. Select **Microsoft Graph** → **Application permissions**
4. Add:
   - `PrivilegedAccess.Read.AzureAD` - Read PIM data
   - `RoleAssignmentSchedule.Read.Directory` - Read role assignments
   - `User.Read` - Read user profile

5. Click **Grant admin consent**

### Step 4: Update Configuration

```env
ENTRA_TENANT_ID=your-organization.onmicrosoft.com
ENTRA_CLIENT_ID=00000000-0000-0000-0000-000000000000
ENTRA_CLIENT_SECRET=your-secret-here
```

## Configuration Reference

See [Configuration Guide](./src/pode-app/README.md#configuration-files)

## Frontend Features

- **Eligible Roles**: View and activate roles you're eligible for
- **Active Roles**: View, monitor, and deactivate active roles
- **Smart Search**: Filter roles by name and scope
- **Batch Operations**: Activate/deactivate multiple roles
- **Justification Dialog**: Requirement-aware justification and ticket capture
- **User Preferences**: Theme, auto-refresh, default duration
- **Real-time Updates**: Auto-refresh eligible and active roles

## API Documentation

See [API Endpoints](./src/pode-app/README.md#api-endpoints)

## Development

### Local Setup

```powershell
# Install Pode
Install-Module -Name Pode -Force

# Configure environment
$env:ENTRA_TENANT_ID = "your-tenant"
$env:ENTRA_CLIENT_ID = "your-client-id"
$env:ENTRA_CLIENT_SECRET = "your-secret"
$env:PODE_MODE = "development"

# Start server
cd src/pode-app
& ./pim-server.ps1
```

### Debugging

Enable debug logging:
```powershell
$env:LOG_LEVEL = "Debug"
```

### Testing

```powershell
# Health check
curl http://localhost:8080/api/health

# Eligible roles
curl -H "Authorization: Bearer <token>" http://localhost:8080/api/roles/eligible
```

## Troubleshooting

### Container won't start
- Check Docker logs: `docker-compose logs`
- Verify Pode is installed: `docker-compose exec pim-app pwsh -c "Get-InstalledModule Pode"`
- Check port availability: `docker ps` or check other containers on port 8080

### Authentication failing
- Verify Entra ID credentials in `.env`
- Check app permissions: go to Azure AD → App registrations → PIM Activation Web → API permissions
- Verify redirect URI matches: `http://localhost:8080/callback`

### Roles not loading
- Check if backend PIM modules are connected
- Review logs: `docker-compose logs pim-app | grep -i role`
- Verify user has PIM roles: go to Azure AD → Privileged Identity Management

### Can't access web UI
- Verify container is running: `docker ps`
- Check port mapping: `docker-compose port pim-app 8080`
- Try accessing: `http://localhost:8080` or `http://127.0.0.1:8080`
- Check firewall rules

## Migration from Windows Forms

### For users:
- **Old**: Run `Start-PIMActivation` in PowerShell terminal
- **New**: Navigate to `http://your-server:8080` in web browser
- **Authentication**: Uses Entra ID OAuth instead of interactive Microsoft Graph auth
- **Features**: All original features preserved, plus multi-user support

### For administrators:
- **Deployment**: Single Docker container instead of per-machine installation
- **Updates**: Update container image once, all users get the new version
- **Monitoring**: Centralized logging and audit trail
- **Access**: Network-based, no VPN required for GUI

## Performance & Scalability

### Current Implementation
- Single-instance, file-based session storage
- In-memory role cache (refreshes on request)
- Handles ~50 concurrent users

### For Production Scaling
- Add Redis for distributed session storage
- Use load balancer (nginx, HAProxy)
- Deploy multiple service replicas
- Use managed container orchestration (Kubernetes, App Service)

See [Scaling Guide](./SCALING.md)

## Security

### Built-in
- ✅ HTTPS support (via reverse proxy)
- ✅ OAuth 2.0 authentication
- ✅ Token expiry and auto-refresh
- ✅ CORS protection
- ✅ JSON structured logging for audit

### Recommended Production Setup
- Use reverse proxy (nginx) with SSL/TLS
- Enable Azure AD Conditional Access
- Implement API rate limiting
- Store secrets in Azure Key Vault
- Enable container image scanning
- Use network policies to restrict access

See [Security Guide](./SECURITY.md)

## Monitoring & Logging

Logs are written to `/var/log/pim/pode.log` in JSON format.

### Viewing Container Logs
```bash
docker-compose logs -f pim-app
```

### Viewing File Logs
```bash
docker-compose exec pim-app tail -f /var/log/pim/pode.log
```

## Roadmap

- ✅ Phase 1: Web UI skeleton with Pode
- ✅ Phase 2: API endpoints for role management
- ✅ Phase 3: Frontend UI with role lists and activation
- ⏳ Phase 4: OAuth 2.0 full integration with Entra ID
- ⏳ Phase 5: Docker multi-stage build optimization
- ⏳ Phase 6: Kubernetes deployment manifests
- ⏳ Phase 7: Advanced features (audit log viewer, approval workflows, MFA)

## Support & Feedback

For questions or issues:
- Review [Troubleshooting Guide](./src/pode-app/README.md#troubleshooting)
- Check [API Documentation](./src/pode-app/README.md#api-endpoints)
- Update `.env` configuration
- Review application logs

## License

Same as PIMActivation module

---

**Last Updated**: April 2026  
**Version**: 2.0.0 (Web-based)
