# PIMActivation Web Migration - Current State

## Project Overview
Migrating PIMActivation from Windows Forms to a web-based UI using Pode (PowerShell HTTP framework) in Docker containers.

## Technical Stack
- **Backend**: Pode server with PowerShell 7
- **Frontend**: Vanilla JavaScript with Fluent Design System CSS
- **Container**: Docker with Alpine Linux base image
- **Authentication**: OAuth 2.0 (currently stubbed, needs Entra ID integration)
- **API**: REST endpoints for PIM role management

## Current Status
- ✅ Full web infrastructure implemented (Pode server, API routes, frontend UI, Docker config)
- ✅ Docker image build fixed (updated from deprecated mcr.microsoft.com/powershell:7-alpine to mcr.microsoft.com/dotnet/sdk:8.0-alpine)
- ✅ Docker image successfully built and loaded (pim-activation-web:latest, 733MB)
- ❌ Docker Compose startup failing due to missing host directories

## Last Error
```
Error response from daemon: container create: statfs /mnt/c/lukas/repos/PIMActivation/config: no such file or directory
```

## Required Directories
The docker-compose.yml requires these host directories for volume mounting:
- `./config` → `/etc/pim-config:ro`
- `./logs` → `/var/log/pim:rw`
- `pim-data` (named volume) → `/var/pim-data`

## Next Steps
1. Create missing directories: `config` and `logs`
2. Run `docker-compose up -d` to start the container
3. Access web UI at http://localhost:8080
4. Configure Entra ID OAuth (update .env file with tenant/client IDs)
5. Integrate real PIM PowerShell functions (replace stubs in PIMApiLayer.ps1)

## Files Created/Modified
- `src/pode-app/pim-server.ps1` - Main Pode server
- `src/pode-app/PIMApiLayer.ps1` - API wrapper (stubs)
- `src/pode-app/index.html` - Single-page web UI
- `src/pode-app/api-client.js` - Frontend API client
- `src/pode-app/roles.js` - Role management UI logic
- `Dockerfile` - Multi-stage build with .NET SDK Alpine
- `docker-compose.yml` - Service orchestration
- `.env.example` - Environment variables template
- Documentation: `QUICK-START-WEB.md`, `DEPLOYMENT-WEB.md`, `README.md`

## Environment Setup
- Docker Desktop installed on Windows
- PowerShell 7 available
- Pode module installed in container
- Host directories created for volumes

## Pending Integrations
- Real Entra ID OAuth flow
- Actual PIM PowerShell function calls
- Persistent data storage
- End-to-end testing

## Commands to Run Next
```bash
mkdir config logs
docker-compose up -d
# Then access http://localhost:8080
```