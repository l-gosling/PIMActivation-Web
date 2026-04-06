# Contributing to PIM Activation Web

Thank you for your interest in contributing! This is a Docker-based web application built with PowerShell (Pode) and vanilla JavaScript.

## Quick Start

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/[YourUsername]/PIMActivation.git`
3. **Create** a feature branch: `git checkout -b feature/amazing-feature`
4. **Configure** your `.env` file (see [README.md](README.md))
5. **Build & run**: `docker compose up -d --build`
6. **Make** your changes
7. **Rebuild & test**: `docker compose down && docker compose up -d --build`
8. **Commit** with clear messages: `git commit -m 'Add amazing feature'`
9. **Push** to your branch: `git push origin feature/amazing-feature`
10. **Open** a Pull Request

## Development Environment

### Prerequisites

- Docker and Docker Compose
- An Entra ID app registration with the required permissions (see [README.md](README.md))
- A text editor (VS Code recommended for PowerShell + JS support)

### Running Locally

```bash
cp .env.example .env
# Edit .env with your Entra ID credentials
mkdir -p certs
openssl req -x509 -newkey rsa:4096 -keyout certs/key.pem -out certs/cert.pem -days 365 -nodes -subj "/CN=localhost"
docker compose up -d --build
```

Open https://localhost in your browser.

### Viewing Logs

```bash
docker compose logs -f
```

### Rebuilding After Changes

After editing any file under `src/pode-app/`, rebuild the container:

```bash
docker compose down && docker compose up -d --build
```

## Project Structure

| Path | Language | Purpose |
|------|----------|---------|
| `src/pode-app/pim-server.ps1` | PowerShell | Server entry point, route registration |
| `src/pode-app/modules/` | PowerShell | Backend modules (logging, config, API layer) |
| `src/pode-app/middleware/` | PowerShell | OAuth 2.0, session management |
| `src/pode-app/routes/` | PowerShell | HTTP route handlers |
| `src/pode-app/public/js/` | JavaScript | Frontend SPA (vanilla, no framework) |
| `src/pode-app/public/css/` | CSS | Fluent Design styling (light + dark theme) |
| `Dockerfile` | Docker | Container build definition |
| `docker-compose.yml` | YAML | Service orchestration |

For detailed architecture, see [architecture.md](architecture.md). For Pode framework concepts, see [pode-onboarding.md](pode-onboarding.md).

## Ways to Contribute

- **Bug Reports**: Found something broken? Open an issue with steps to reproduce.
- **Feature Requests**: Have an idea? Open an issue describing the use case.
- **Documentation**: Improve docs, add examples, fix typos.
- **Code**: Fix bugs, add features, improve performance.

## Code Guidelines

### PowerShell (Backend)

- Use `[CmdletBinding()]` on all functions
- Add `[Parameter(Mandatory)]` and `[ValidateNotNullOrEmpty()]` where appropriate
- Use `Write-Log` for all logging (not `Write-Host`)
- Use `Assert-AuthenticatedSession` for auth guards in route handlers
- Use `Get-CurrentSessionContext` for session/token access (not manual cookie lookup)
- Use `Invoke-WebRequest` for HTTP calls (not curl)
- Follow existing naming: `Invoke-*` for route handlers, `Get-*`/`Set-*`/`New-*` for helpers

### JavaScript (Frontend)

- Vanilla JS only (no frameworks, no build step)
- Use `escapeHtml()` for all user-provided text rendered in HTML
- Use `window.apiClient` for all API calls
- Use `showToast()` / `showErrorToast()` for notifications
- Use `showProgress()` / `updateProgress()` / `hideProgress()` for batch operations
- Support both light and dark themes in CSS

### CSS

- Use CSS custom properties (e.g., `var(--primary-color)`)
- Add `.dark-theme` overrides for dark mode (use explicit hex colors, not inverted CSS variables)
- Follow the existing section comment structure

## Before You Submit

- Code follows the guidelines above
- Changes work in both light and dark themes
- Container builds and starts without errors
- All existing features still work (roles, activation, profiles, history)
- Documentation is updated if needed
- Commit messages are clear and descriptive

## License

By contributing, you agree that your contributions will be licensed under the same [MIT License](LICENSE) that covers this project.
