FROM alpine:3.21

LABEL org.opencontainers.image.source="https://github.com/dublyo/postgresql-cloudbackup"
LABEL org.opencontainers.image.description="Automated PostgreSQL backups to S3-compatible storage (R2, MinIO, AWS S3, Backblaze B2)"
LABEL org.opencontainers.image.licenses="MIT"

# Install multiple PostgreSQL client versions (pg_dump) so we can match any server.
# pg_dump is backward-compatible: a newer pg_dump can dump older servers.
# We install the latest available (from edge) to cover the widest range.
RUN echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories \
    && apk add --no-cache \
    postgresql16-client \
    aws-cli \
    bash \
    gzip \
    curl \
    tzdata \
    && rm -rf /var/cache/apk/* \
    # Save pg16 binary, then install pg17 (replaces /usr/bin/pg_dump)
    && cp /usr/bin/pg_dump /usr/local/bin/pg_dump16 \
    && apk add --no-cache postgresql17-client \
    && cp /usr/bin/pg_dump /usr/local/bin/pg_dump17 \
    # Install pg18 from edge (latest, replaces /usr/bin/pg_dump again)
    && apk add --no-cache postgresql18-client@edge \
    && cp /usr/bin/pg_dump /usr/local/bin/pg_dump18

# Create app directory and non-root user
RUN addgroup -S backup && adduser -S backup -G backup \
    && mkdir -p /app /tmp/backups \
    && chown -R backup:backup /app /tmp/backups

WORKDIR /app

COPY --chown=backup:backup backup.sh /app/backup.sh
COPY --chown=backup:backup entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/backup.sh /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
