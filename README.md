# PostgreSQL Cloud Backup

Automated PostgreSQL backups to any S3-compatible cloud storage.

Lightweight Docker container that runs `pg_dump` on a cron schedule, compresses with gzip, uploads to S3-compatible storage, and enforces a retention policy.

## Supported Storage Providers

Any S3-compatible storage works out of the box:

| Provider | Endpoint Example |
|----------|-----------------|
| **Cloudflare R2** | `https://<account-id>.r2.cloudflarestorage.com` |
| **MinIO** | `https://minio.example.com:9000` |
| **AWS S3** | `https://s3.amazonaws.com` |
| **Backblaze B2** | `https://s3.us-west-000.backblazeb2.com` |
| **DigitalOcean Spaces** | `https://nyc3.digitaloceanspaces.com` |
| **Wasabi** | `https://s3.wasabisys.com` |

## Quick Start

```bash
docker run -d --name pg-backup \
  -e POSTGRES_HOST=your-db-host \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=your-password \
  -e POSTGRES_DB=your-database \
  -e BACKUP_SCHEDULE=daily \
  -e BACKUP_TIME=03:00 \
  -e BACKUP_RETENTION=3 \
  -e S3_ENDPOINT=https://your-endpoint.com \
  -e S3_ACCESS_KEY=your-access-key \
  -e S3_SECRET_KEY=your-secret-key \
  -e S3_BUCKET=your-bucket \
  ghcr.io/dublyo/postgresql-cloudbackup:latest
```

## Docker Compose

```yaml
services:
  postgres:
    image: postgres:17
    environment:
      POSTGRES_PASSWORD: secret123
      POSTGRES_DB: myapp
    volumes:
      - pgdata:/var/lib/postgresql/data

  pg-backup:
    image: ghcr.io/dublyo/postgresql-cloudbackup:latest
    depends_on:
      - postgres
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: secret123
      POSTGRES_DB: myapp
      BACKUP_SCHEDULE: daily
      BACKUP_TIME: "03:00"
      BACKUP_RETENTION: "3"
      BACKUP_ON_START: "true"
      S3_ENDPOINT: https://your-endpoint.com
      S3_ACCESS_KEY: your-access-key
      S3_SECRET_KEY: your-secret-key
      S3_BUCKET: my-backups
      S3_PATH_PREFIX: "myapp/"

volumes:
  pgdata:
```

## Environment Variables

### PostgreSQL Connection

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POSTGRES_HOST` | Yes | — | PostgreSQL hostname or container name |
| `POSTGRES_PORT` | No | `5432` | PostgreSQL port |
| `POSTGRES_USER` | Yes | — | Database user |
| `POSTGRES_PASSWORD` | Yes | — | Database password |
| `POSTGRES_DB` | Yes | — | Database name to back up |

### Backup Schedule

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `BACKUP_SCHEDULE` | No | `daily` | `daily`, `weekly`, `every6h`, `every12h`, or a cron expression |
| `BACKUP_TIME` | No | `03:00` | Time to run (HH:MM, UTC) |
| `BACKUP_RETENTION` | No | `3` | Number of backups to keep (1-5+) |
| `BACKUP_ON_START` | No | `false` | Run backup immediately on container start |
| `TZ` | No | `UTC` | Timezone for schedule |

### S3 Storage

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `S3_ENDPOINT` | Yes | — | S3-compatible endpoint URL |
| `S3_ACCESS_KEY` | Yes | — | Access key ID |
| `S3_SECRET_KEY` | Yes | — | Secret access key |
| `S3_BUCKET` | Yes | — | Bucket name |
| `S3_REGION` | No | `auto` | Region (`auto` for R2, `us-east-1` for MinIO) |
| `S3_PATH_PREFIX` | No | `backups/` | Folder prefix inside bucket |

## How It Works

1. **Cron fires** at the configured schedule
2. **pg_dump** exports the database in plain SQL format
3. **gzip -9** compresses the dump (typically 80-90% reduction)
4. **aws s3 cp** uploads to your S3-compatible bucket
5. **Retention** lists backups and deletes the oldest beyond the retention count

### Backup File Naming

```
backups/mydb-20260213-030000.sql.gz
backups/mydb-20260214-030000.sql.gz
backups/mydb-20260215-030000.sql.gz
```

### Restoring a Backup

Download and restore manually:

```bash
# Download
aws s3 cp s3://your-bucket/backups/mydb-20260213-030000.sql.gz ./backup.sql.gz \
  --endpoint-url https://your-endpoint.com

# Restore
gunzip -c backup.sql.gz | psql -h your-host -U postgres -d your-database
```

## Dublyo PaaS

This template is available on [Dublyo](https://dublyo.com) as a one-click deploy. Deploy it alongside your PostgreSQL database and configure storage via the dashboard.

## License

MIT
