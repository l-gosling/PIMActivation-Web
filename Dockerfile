# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git

WORKDIR /tmp/build

# Copy the entire PIMActivation module
COPY . .

# Install Pode
RUN pwsh -Command "Install-Module -Name Pode -Force -Scope AllUsers"

# Runtime stage
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine

# Install runtime dependencies
RUN apk add --no-cache \
    curl \
    tini \
    ca-certificates \
    icu-libs

# Install Pode
RUN pwsh -Command "Install-Module -Name Pode -Force -Scope AllUsers"

# Create app directory
WORKDIR /app

# Copy application code
COPY ./src/pode-app .

# Create data and cert directories
RUN mkdir -p /var/pim-data/preferences \
    /var/pim-data/logs \
    /etc/pim-config \
    /etc/pim-certs

# Set proper permissions (700 for data dirs — only the app process needs access)
RUN chmod -R 755 /app && \
    chmod -R 700 /var/pim-data && \
    chmod -R 700 /etc/pim-config && \
    chmod -R 755 /etc/pim-certs

# Expose ports (8080 = HTTPS, 8081 = HTTP redirect)
EXPOSE 8080 8081

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -kf https://localhost:8080/api/health 2>/dev/null || curl -f http://localhost:8080/api/health || exit 1

# Use tini to handle signals properly
ENTRYPOINT ["/sbin/tini", "--"]

# Start the Pode server
CMD ["pwsh", "-Command", "& /app/pim-server.ps1"]
