FROM alpine:3.21

LABEL org.opencontainers.image.source="https://github.com/dublyo/postgresql-cloudbackup"
LABEL org.opencontainers.image.description="Automated PostgreSQL backups to S3-compatible storage (R2, MinIO, AWS S3, Backblaze B2)"
LABEL org.opencontainers.image.licenses="MIT"

# Install multiple pg_dump versions so we can match any server (16, 17, 18).
# Alpine won't overwrite /usr/bin/pg_dump when a second pg client is installed,
# so we install each version alone, save the binary, then remove before the next.
# The last version (pg18) stays installed to provide psql, pg_isready, and libpq.
# All pg_dump binaries link against libpq.so.5 which is ABI-compatible across versions.
# Install pg18 client first (provides psql, pg_isready, pg_dump, and libpq)
# Then install older pg_dump binaries using static-ish approach:
# save each pg_dump binary before removing the client package.
# All pg_dump versions link against libpq.so.5 — we keep pg18's libpq.
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
    # Verify psql works with this libpq
    && psql --version \
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
