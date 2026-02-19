FROM alpine:3.21

LABEL org.opencontainers.image.source="https://github.com/dublyo/postgresql-cloudbackup"
LABEL org.opencontainers.image.description="Automated PostgreSQL backups to S3-compatible storage (R2, MinIO, AWS S3, Backblaze B2)"
LABEL org.opencontainers.image.licenses="MIT"

# Install pg_dump for versions 16, 17, 18 so we can match any server.
# Each version is installed alone, its pg_dump binary is saved, then removed.
# pg18 is installed LAST and KEPT (provides pg_isready and libpq.so.5).
# All saved pg_dump binaries link against libpq.so.5 which is ABI-compatible.
RUN echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories \
    && apk add --no-cache aws-cli bash gzip curl tzdata \
    # pg16: install, save binary, remove
    && apk add --no-cache postgresql16-client \
    && cp /usr/bin/pg_dump /usr/local/bin/pg_dump16 \
    && /usr/local/bin/pg_dump16 --version \
    && apk del --no-cache postgresql16-client \
    # pg17: install, save binary, remove
    && apk add --no-cache postgresql17-client \
    && cp /usr/bin/pg_dump /usr/local/bin/pg_dump17 \
    && /usr/local/bin/pg_dump17 --version \
    && apk del --no-cache postgresql17-client \
    # pg18 from edge: install LAST and KEEP (provides psql + pg_isready + matching libpq)
    && apk add --no-cache postgresql18-client@edge \
    && cp /usr/bin/pg_dump /usr/local/bin/pg_dump18 \
    && /usr/local/bin/pg_dump18 --version \
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
