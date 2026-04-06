# Changelog

All notable changes to PIM Activation Web will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-04-06

### Complete Web Rewrite

Full rewrite from a Windows Forms PowerShell module to a Docker-based web application using Pode (PowerShell HTTP server) with a vanilla JavaScript SPA frontend.

### Added

- **Web-Based SPA** — browser-accessible UI with Fluent Design styling, dark/light theme support
- **Pode Backend** — PowerShell 7 HTTP server with 5-thread pool, running on Alpine Linux in Docker
- **OAuth 2.0 Authentication** — Entra ID Authorization Code flow with automatic token refresh
- **Entra ID Roles** — eligible/active role listing, activation, deactivation with AU scope support
- **PIM Groups** — PIM-enabled group membership management (member/owner)
- **Azure Resource Roles** — cross-subscription Azure PIM role management via dual-token strategy
- **Saved Profiles** — save frequently used role combinations and activate them with two clicks
- **Activation History** — local event recording with analytics (success rate, most activated roles, activity by day)
- **Entra Audit Log Sync** — background fetch of PIM events from Entra audit logs (last 30 days, max 100 entries) with deduplication against local history
- **Progress Bar** — visual batch progress for activation/deactivation with current role name and scope
- **Policy Enforcement** — automatic duration capping when a role's max duration is lower than the selected duration, with warning in progress bar and toast
- **Duration Validation** — server-side validation of activation duration (1-1440 minutes)
- **Security Headers Middleware** — HSTS, X-Frame-Options (DENY), X-Content-Type-Options (nosniff), Referrer-Policy, Permissions-Policy on all responses
- **SameSite Cookies** — custom `Set-SecureCookie` helper for SameSite=Lax (Pode 2.x lacks native support)
- **Session Expiry Enforcement** — `Assert-AuthenticatedSession` checks expiry on every protected request, not just timer cleanup
- **Structured Logging** — JSON-formatted logs with level filtering (Verbose through Error) via `Write-Log`
- **Per-User Preferences** — server-side JSON storage (theme, sort, Azure visibility, profiles, history) with SHA256-hashed filenames
- **Docker Deployment** — Alpine Linux container with tini, healthcheck, named volume for persistent data
- **Customizable Theming** — full color, font, and branding customization via environment variables

### Security

- OAuth 2.0 Authorization Code flow with CSRF protection (state parameter)
- HttpOnly + Secure + SameSite=Lax session cookies
- Cryptographic session IDs (48-byte random, Base64url-safe)
- `Invoke-WebRequest` for all HTTP calls (no curl, no tokens in process args, no temp files)
- Google DNS (8.8.8.8) in docker-compose.yml to fix .NET IPv6 DNS resolution on Alpine
- Thread-safe session state with `Lock-PodeObject` for all write operations
- File permissions at 700 for preference storage directory
- `[CmdletBinding()]` and `[ValidateNotNullOrEmpty()]` on all PowerShell functions

### Architecture

- Helper functions to eliminate duplicated patterns: `Get-CurrentSessionContext`, `Assert-AuthenticatedSession`, `Resolve-DirectoryScopeDisplay`, `New-EntraRoleEntry`, `New-GroupRoleEntry`, `New-AzureRoleEntry`, `Get-AzureRoleVisibility`
- All `Write-Host` calls replaced with structured `Write-Log` (38 replacements)
- Consistent variable naming (`$roleAssignment` instead of `$r`, `$sessionId` instead of `$sid`)
- Preferences system extended with `json` type for profiles and history arrays

---

## [2.0.0] - 2025-12-29

### Initial Web Version

- Pode-based REST API with SPA frontend
- Entra ID roles, PIM groups, Azure resource roles
- OAuth 2.0 authentication
- Docker container deployment
- Basic theme and preference support
