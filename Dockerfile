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

# Create data directories
RUN mkdir -p /var/pim-data/preferences \
    /var/pim-data/logs \
    /etc/pim-config

# Set proper permissions
RUN chmod -R 755 /app && \
    chmod -R 777 /var/pim-data && \
    chmod -R 777 /etc/pim-config

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/api/health || exit 1

# Use tini to handle signals properly
ENTRYPOINT ["/sbin/tini", "--"]

# Start the Pode server
CMD ["pwsh", "-Command", "& /app/pim-server.ps1"]
