# PIM Activation - Web UI Quick Start Guide

## What Was Implemented

### ✅ Infrastructure
- **Dockerfile**: Multi-stage Alpine Linux build with PowerShell 7 + Pode
- **docker-compose.yml**: Production-ready configuration with volumes, health checks, environment vars
- **.env.example**: Configuration template for Entra ID setup
- **.dockerignore**: Optimized build context

### ✅ Backend (Pode)
- **pim-server.ps1**: Main server entry point with route configuration
- **modules/**:
  - `Logger.ps1` - JSON structured logging
  - `Configuration.ps1` - Environment-based config management
  - `SessionManager.ps1` - Thread-safe session/token storage
  - `PIMApiLayer.ps1` - Stubs for PIM API functions (ready to integrate)
- **middleware/**:
  - `AuthMiddleware.ps1` - OAuth token validation
  - `ErrorMiddleware.ps1` - Consistent error responses
  - `LoggingMiddleware.ps1` - HTTP request logging
- **routes/**:
  - `Auth.ps1` - Login/logout endpoints
  - `Roles.ps1` - Role activation/deactivation endpoints
  - `Config.ps1` - Feature and theme configuration

### ✅ Frontend (Web UI)
- **index.html**: Complete single-page application shell with:
  - Login screen
  - Header with user menu and refresh button
  - Sidebar navigation (Eligible/Active roles)
  - Role list panels with search/filter
  - Activation dialog modal (justification, ticket, duration)
  - Preferences modal
  - Toast notifications

- **css/style.css**: Full Fluent Design System styling:
  - Entra ID blue (#0078D4) primary color
  - Responsive layout (Flexbox)
  - Buttons, forms, modals with Microsoft styles
  - Mobile-friendly breakpoints
  - Accessibility-focused design

- **js/**:
  - `api-client.js` - API wrapper with token management and refresh
  - `auth.js` - OAuth login/logout flow and session management
  - `roles.js` - Role list rendering, filtering, selection, batch operations
  - `activation.js` - Activation/deactivation dialogs
  - `app.js` - Main application initialization and keyboard shortcuts

### ✅ Documentation
- **src/pode-app/README.md**: Comprehensive guide including:
  - Directory structure
  - Local development setup
  - Docker deployment
  - API endpoint reference
  - Configuration options
  - Troubleshooting
  
- **DEPLOYMENT-WEB.md**: Migration guide covering:
  - Technology stack overview
  - Quick start instructions
  - Entra ID setup (step-by-step)
  - Kubernetes deployment reference
  - Security best practices
  - Scaling guidance

---

## Next Steps (To Complete Full Integration)

### 1. **Integrate Real PIM Functions**
   - **File**: `src/pode-app/modules/PIMApiLayer.ps1`
   - **Replace**: The stub functions with actual calls to existing PIM PowerShell functions
   - **Examples**:
     ```powershell
     # Instead of stubs, call real functions
     Get-PIMEligibleRolesForWeb → calls Get-PIMEligibleRoles
     Invoke-PIMRoleActivationForWeb → calls Invoke-PIMRoleActivation
     ```
   - **Impact**: Enable role activation, deactivation, and policy checking
   - **Time**: 2-3 hours

### 2. **Implement OAuth 2.0 with Entra ID**
   - **File**: `src/pode-app/middleware/AuthMiddleware.ps1`
   - **Current**: Accepts any bearer token
   - **Needed**: Validate JWT tokens with Entra ID token endpoint
   - **Libraries**: Use MSAL.PS or direct REST calls to `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token`
   - **Time**: 2-3 hours

### 3. **Enable Persistent Data Storage**
   - **Preferences**: Load/save user preferences to `/var/pim-data/`
   - **Cache**: Implement role cache with TTL
   - **Logs**: Ensure JSON logs write to persistent volume
   - **Time**: 1-2 hours

### 4. **Test End-to-End**
   - Build Docker image: `docker build -t pim-activation-web:latest .`
   - Run container: `docker-compose up`
   - Test in browser: `http://localhost:8080`
   - Login, view roles, activate a test role
   - **Time**: 1-2 hours

### 5. **Add Multi-User/Multi-Instance Support** (Optional)
   - Replace file-based sessions with Redis
   - Enable horizontal scaling
   - Add load balancer configuration
   - **Time**: 2-4 hours

### 6. **Security Hardening** (Production)
   - Add HTTPS/TLS (via reverse proxy)
   - Implement rate limiting
   - Add audit logging for role activations
   - Use Azure Key Vault for secrets
   - Enable Conditional Access in Entra ID
   - **Time**: 3-4 hours

---

## Current Status

| Component | Status | Notes |
|-----------|--------|-------|
| Docker infrastructure | ✅ Ready | Build and run immediately |
| Pode server framework | ✅ Ready | All routes defined |
| Frontend UI | ✅ Ready | Fully functional mock implementation |
| OAuth authentication | ✅ Stub | Uses mock tokens, needs Entra ID integration |
| PIM API integration | ✅ Stub | Placeholder functions, needs real PIM calls |
| Persistent storage | ⚠️ Partial | Volumes configured, functions need implementation |
| Production ready | ❌ Not yet | Need OAuth + PIM integration + security hardening |

---

## File Locations (Reference)

### Backend Files
- Server: `/src/pode-app/pim-server.ps1`
- Middleware: `/src/pode-app/middleware/`
- Routes: `/src/pode-app/routes/`
- Modules: `/src/pode-app/modules/`

### Frontend Files  
- HTML: `/src/pode-app/public/index.html`
- CSS: `/src/pode-app/public/css/style.css`
- JavaScript: `/src/pode-app/public/js/*.js`

### Configuration
- Docker: `/Dockerfile`
- Compose: `/docker-compose.yml`
- Env template: `/.env.example`

### Documentation
- Web app guide: `/src/pode-app/README.md`
- Deployment guide: `/DEPLOYMENT-WEB.md`
- (This file): `/QUICK-START-WEB.md`

---

## Testing the Current Implementation

### 1. Build the Docker image
```bash
docker build -t pim-activation-web:latest .
```

### 2. Start the container
```bash
docker-compose up -d
```

### 3. Access the UI
```
http://localhost:80
```

### 4. Click "Sign in with Entra ID"
- Currently shows mock data
- Real implementation will redirect to Entra ID

### 5. View mock roles
- Frontend and styling: ✅ Working
- API responses: ✅ Mock data returned
- Role activation: ⏳ Needs real PIM integration

### 6. Check container health
```bash
docker-compose ps
docker-compose logs
```

---

## Key Design Decisions

### Why Pode?
- Runs in PowerShell 7 (same environment as existing PIM module)
- Minimal dependencies
- REST API framework suitable for lightweight services
- Reuses existing PowerShell knowledge

### Why Docker?
- Centralized deployment
- Multi-user support (vs. per-machine Windows Forms install)
- Enterprise-ready with volume persistence and health checks
- Can run on Linux servers

### Why Web-based?
- Network-accessible (VPN optional)
- Updates deployed once, available to all users
- Modern browser UI better than Windows Forms
- Supports OAuth/SSO integration
- Cross-platform (Windows, Mac, Linux)

---

## Key Configuration Needed

### Required Environment Variables
```env
ENTRA_TENANT_ID=your-org.onmicrosoft.com
ENTRA_CLIENT_ID=<from Azure AD app registration>
ENTRA_CLIENT_SECRET=<from Azure AD app registration>
```

### Optional for Development
```env
PODE_MODE=development         # dev mode for verbose logging
LOG_LEVEL=Debug              # detailed logging
SESSION_TIMEOUT=7200         # 2 hours
```

---

## Support for Next Phase

When ready to implement the real integrations, refer to:

1. **OAuth Integration**: See Azure AD / MSAL.PS documentation
2. **PIM Functions**: Existing `/Private/RoleManagement/` PowerShell modules
3. **Graph API**: Microsoft.Graph PowerShell module
4. **Error Handling**: Consistent HTTP error responses already defined

---

**Implementation Time Estimate**: 
- **Current (mock)**: Complete ✅
- **Full integration**: 8-12 hours
- **Production hardening**: 4-6 hours
- **Total**: 12-18 hours

**Last Updated**: April 6, 2026
