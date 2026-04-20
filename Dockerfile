# Single stage — the previous builder stage was dead code (its output was never
# used by the runtime stage). Switched from `dotnet/sdk:8.0-alpine` to the
# dedicated PowerShell image to eliminate the .NET SDK attack surface
# (MSBuild + System.Security.Cryptography.Xml accounted for 7 HIGH CVEs).
FROM mcr.microsoft.com/powershell:7.5-alpine-3.20

# Apply Alpine security patches, install tini (PID 1 signal handler), and drop
# `less` which ships with the PowerShell image but is not used by a non-interactive
# service (and carries an unpatched HIGH CVE-2024-32487). curl is intentionally
# omitted — the HEALTHCHECK below uses pwsh's Invoke-WebRequest instead.
# We swap the default `dl-cdn.alpinelinux.org` mirror (which has been flaky for
# the `/main` repo specifically) for `dl-4.alpinelinux.org` at build time only.
RUN sed -i 's|https://dl-cdn.alpinelinux.org/alpine|https://dl-4.alpinelinux.org/alpine|g' /etc/apk/repositories && \
    apk upgrade --no-cache && \
    apk add --no-cache tini && \
    apk del --no-cache less && \
    sed -i 's|https://dl-4.alpinelinux.org/alpine|https://dl-cdn.alpinelinux.org/alpine|g' /etc/apk/repositories

# Install Pode, pinned so rebuilds are reproducible (avoids a future release
# silently rolling in via `-Force` without code review).
RUN pwsh -NoProfile -Command "Install-Module -Name Pode -RequiredVersion 2.13.0 -Force -Scope AllUsers"

# Create unprivileged user the container will run as. addgroup/adduser -D is
# BusyBox-style; -S creates a system group/user (no login, no home).
RUN addgroup -g 10001 -S pim && adduser -u 10001 -S pim -G pim

WORKDIR /app

# Copy app code with the right ownership in a single step (no separate chown layer).
COPY --chown=pim:pim ./src/pode-app .

# Pre-create mounted paths owned by pim so the container can write preferences/logs
# and read certs without needing root at runtime.
RUN mkdir -p /var/pim-data/preferences /var/pim-data/logs /etc/pim-config /etc/pim-certs && \
    chown -R pim:pim /var/pim-data /etc/pim-config /etc/pim-certs && \
    chmod 755 /app && \
    chmod 700 /var/pim-data /etc/pim-config && \
    chmod 755 /etc/pim-certs

EXPOSE 8080 8081

# Healthcheck via pwsh — replaces curl to drop the curl/nghttp2 CVE surface.
# Tries HTTPS first; falls back to HTTP when no cert is mounted (Pode's own fallback).
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD pwsh -NoProfile -Command "try { Invoke-WebRequest -SkipCertificateCheck -Uri https://localhost:8080/api/health -UseBasicParsing -TimeoutSec 5 | Out-Null; exit 0 } catch { try { Invoke-WebRequest -Uri http://localhost:8080/api/health -UseBasicParsing -TimeoutSec 5 | Out-Null; exit 0 } catch { exit 1 } }"

USER pim

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["pwsh", "-Command", "& /app/pim-server.ps1"]
