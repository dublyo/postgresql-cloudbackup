FROM alpine:3.21

LABEL org.opencontainers.image.source="https://github.com/dublyo/postgresql-cloudbackup"
LABEL org.opencontainers.image.description="Automated PostgreSQL backups to S3-compatible storage (R2, MinIO, AWS S3, Backblaze B2)"
LABEL org.opencontainers.image.licenses="MIT"

# Install PostgreSQL 17 client (pg_dump) + aws-cli + utilities
RUN apk add --no-cache \
    postgresql17-client \
    aws-cli \
    bash \
    gzip \
    curl \
    tzdata \
    && rm -rf /var/cache/apk/*

# Create app directory and non-root user
RUN addgroup -S backup && adduser -S backup -G backup \
    && mkdir -p /app /tmp/backups \
    && chown -R backup:backup /app /tmp/backups

WORKDIR /app

COPY --chown=backup:backup backup.sh /app/backup.sh
COPY --chown=backup:backup entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/backup.sh /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
