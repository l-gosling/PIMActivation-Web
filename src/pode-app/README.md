# PIM Activation - Web UI (Pode)

This directory contains the web-based PIM Activation UI built with Pode (PowerShell HTTP framework).

## Directory Structure

```
.
├── pim-server.ps1          # Main Pode server entry point
├── public/
│   ├── index.html          # Main application HTML
│   ├── css/
│   │   └── style.css       # Fluent Design styling
│   └── js/
│       ├── app.js          # Main application
│       ├── api-client.js   # API communication
│       ├── auth.js         # Authentication management
│       ├── roles.js        # Role management
│       └── activation.js   # Role activation dialog
├── routes/
│   ├── Auth.ps1            # Authentication endpoints
│   ├── Roles.ps1           # Role management endpoints
│   ├── Config.ps1          # Configuration endpoints
│   └── Health.ps1          # Health check endpoint
├── middleware/
│   ├── AuthMiddleware.ps1  # Authentication middleware
│   ├── ErrorMiddleware.ps1 # Error handling
│   └── LoggingMiddleware.ps1  # Request logging
└── modules/
    ├── Logger.ps1          # Logging utilities
    ├── Configuration.ps1   # Configuration management
    ├── SessionManager.ps1  # Session/token management
    └── PIMApiLayer.ps1     # API layer for PIM functions
```

## Prerequisites

- PowerShell 7.0+
- Pode module (installed automatically in Docker)
- Docker (for containerized deployment)

## Local Development

### Setup

1. **Install Pode module:**
   ```powershell
   Install-Module -Name Pode -Force -Scope CurrentUser
   ```

2. **Configure environment variables** (copy from `.env.example`):
   ```powershell
   $env:ENTRA_TENANT_ID = "your-tenant-id"
   $env:ENTRA_CLIENT_ID = "your-client-id"
   $env:ENTRA_CLIENT_SECRET = "your-client-secret"
   $env:PODE_PORT = 8080
   $env:PODE_MODE = "development"
   ```

3. **Start the server:**
   ```powershell
   cd src/pode-app
   & ./pim-server.ps1 -Port 8080 -Mode development
   ```

4. **Open browser:**
   Navigate to `http://localhost:8080`

## Docker / Podman Deployment

### Build & Run

1. **Build image:**
   ```bash
   docker build -t pim-activation-web:latest .
   ```

2. **Run container:**
   ```bash
   docker run -p 8080:8080 \
     -e ENTRA_TENANT_ID=your-tenant \
     -e ENTRA_CLIENT_ID=your-client-id \
     -e ENTRA_CLIENT_SECRET=your-secret \
     -v pim-data:/var/pim-data \
     pim-activation-web:latest
   ```

### Using Docker Compose

1. **Create `.env` file** from `.env.example`:
   ```bash
   cp .env.example .env
   ```

2. **Update with your Entra ID credentials**

3. **Start services:**
   ```bash
   docker-compose up -d
   ```

4. **View logs:**
   ```bash
   docker-compose logs -f
   ```

## API Endpoints

### Authentication
- `POST /api/auth/login` - Initiate login
- `POST /api/auth/logout` - Logout user
- `GET /api/auth/me` - Get current user info

### Roles
- `GET /api/roles/eligible` - Get eligible roles
- `GET /api/roles/active` - Get active roles
- `POST /api/roles/activate` - Activate a role
- `POST /api/roles/deactivate` - Deactivate a role
- `GET /api/roles/policies/:roleId` - Get role policies

### Configuration
- `GET /api/config/features` - Get feature flags
- `GET /api/config/theme` - Get theme configuration

### User
- `GET /api/user/preferences` - Get user preferences
- `POST /api/user/preferences` - Update user preferences

## Frontend Features

### Keyboard Shortcuts
- `Ctrl+R` / `Cmd+R` - Refresh role list
- `Escape` - Close modals/dialogs
- `Ctrl+A` / `Cmd+A` - Select all roles

### UI Components
- **Eligible Roles** - View and activate roles you're eligible for
- **Active Roles** - View and deactivate currently active roles
- **Activation Dialog** - Provide justification, ticket, and duration for activation
- **User Preferences** - Theme, auto-refresh, and display preferences
- **Toast Notifications** - Success/error/warning messages

## Configuration Files

### Environment Variables (`.env`)
```
ENTRA_TENANT_ID=your-tenant-id
ENTRA_CLIENT_ID=your-app-client-id  
ENTRA_CLIENT_SECRET=your-client-secret
PODE_PORT=8080
PODE_MODE=production
LOG_LEVEL=Information
SESSION_TIMEOUT=3600
INCLUDE_ENTRA_ROLES=true
INCLUDE_GROUPS=true
INCLUDE_AZURE_RESOURCES=false
```

## Authentication

The application uses **OAuth 2.0** with Entra ID. To set up:

1. **Register app in Entra ID:**
   - Navigate to Azure AD App Registrations
   - Create new application
   - Set Redirect URI: `https://your-domain.com/callback` (or `http://localhost:8080/callback` for dev)
   - Create client secret
   - Grant MS Graph API permissions: `PrivilegedAccess.Read.AzureAD`, `PIMOnly.Read.Directory`, etc.

2. **Update `.env`:**
   - Copy Client ID and Secret
   - Update Tenant ID

3. **Restart application**

## Security Considerations

- **HTTPS**: Always use HTTPS in production
- **Token Expiry**: Tokens refresh automatically before expiry
- **CORS**: Restricted to trusted origins in production
- **Secrets**: Store credentials in environment variables or secrets manager
- **Logging**: JSON logs written to `/var/log/pim/`

## Volume Mounts

- `/etc/pim-config` - Configuration files (read-only)
- `/var/pim-data` - Persistent data (preferences, cache, sessions)
- `/var/log/pim` - Application logs

## Troubleshooting

### Port Already in Use
```powershell
# Find process using port 8080
Get-NetTCPConnection -LocalPort 8080

# Or use Docker Compose with different port
docker-compose -e PODE_PORT=8081 up
```

### Cannot Connect to Backend
- Check if container is running: `docker-compose ps`
- Check logs: `docker-compose logs`
- Verify port mapping: `docker-compose port pim-app 8080`

### Authentication Failures
- Verify Entra ID credentials in `.env`
- Check application permissions in Azure AD
- Review logs for OAuth errors

## Performance Tips

- Enable auto-refresh only when needed
- Use batch operations for multiple role activations
- Monitor session timeout to avoid unexpected logouts
- Consider caching eligible/active roles for 5-10 minutes

## Next Steps

1. **Integrate with actual PIM API layer** - Replace stub functions in `modules/PIMApiLayer.ps1` with real PIM operations
2. **Configure SSL/TLS** - Use reverse proxy (nginx) or Let's Encrypt
3. **Add multi-instance support** - Use Redis for session storage
4. **Implement audit logging** - Log all role activations to central store
5. **Add MFA integration** - Support FIDO2, Windows Hello, etc.

## Support

For issues or feature requests, please refer to the main PIMActivation documentation.
