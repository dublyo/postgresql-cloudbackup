#!/bin/bash
set -e

# ============================================
# PostgreSQL Cloud Backup — Entrypoint
# Sets up cron schedule and starts crond
# ============================================

echo "========================================"
echo " PostgreSQL Cloud Backup"
echo " github.com/dublyo/postgresql-cloudbackup"
echo "========================================"

# Validate required env vars
REQUIRED_VARS="POSTGRES_HOST POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB S3_ENDPOINT S3_ACCESS_KEY S3_SECRET_KEY S3_BUCKET"
for var in $REQUIRED_VARS; do
  if [ -z "${!var}" ]; then
    echo "[ERROR] Missing required environment variable: $var"
    exit 1
  fi
done

# Defaults
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-daily}"
BACKUP_TIME="${BACKUP_TIME:-03:00}"
BACKUP_RETENTION="${BACKUP_RETENTION:-3}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
S3_REGION="${S3_REGION:-auto}"
S3_PATH_PREFIX="${S3_PATH_PREFIX:-backups/}"
TZ="${TZ:-UTC}"

# Parse time
HOUR=$(echo "$BACKUP_TIME" | cut -d: -f1)
MINUTE=$(echo "$BACKUP_TIME" | cut -d: -f2)

# Build cron expression
case "$BACKUP_SCHEDULE" in
  daily)
    CRON_EXPR="$MINUTE $HOUR * * *"
    echo "[CONFIG] Schedule: Daily at $BACKUP_TIME"
    ;;
  weekly)
    CRON_EXPR="$MINUTE $HOUR * * 0"
    echo "[CONFIG] Schedule: Weekly (Sunday) at $BACKUP_TIME"
    ;;
  every6h)
    CRON_EXPR="0 */6 * * *"
    echo "[CONFIG] Schedule: Every 6 hours"
    ;;
  every12h)
    CRON_EXPR="0 */12 * * *"
    echo "[CONFIG] Schedule: Every 12 hours"
    ;;
  *)
    # Allow raw cron expression
    CRON_EXPR="$BACKUP_SCHEDULE"
    echo "[CONFIG] Schedule: Custom ($CRON_EXPR)"
    ;;
esac

echo "[CONFIG] Retention: Keep $BACKUP_RETENTION backups"
echo "[CONFIG] Database: $POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
echo "[CONFIG] Storage: $S3_ENDPOINT/$S3_BUCKET/$S3_PATH_PREFIX"
echo "[CONFIG] Timezone: $TZ"

# Configure AWS CLI for S3-compatible storage
mkdir -p /root/.aws
cat > /root/.aws/config <<EOF
[default]
region = $S3_REGION
s3 =
    signature_version = s3v4
EOF

cat > /root/.aws/credentials <<EOF
[default]
aws_access_key_id = $S3_ACCESS_KEY
aws_secret_access_key = $S3_SECRET_KEY
EOF

# Test S3 connection
echo "[INIT] Testing S3 connection..."
if aws s3 ls "s3://$S3_BUCKET" --endpoint-url "$S3_ENDPOINT" > /dev/null 2>&1; then
  echo "[INIT] S3 connection OK"
else
  echo "[WARN] S3 connection test failed — bucket may not exist yet or credentials may be wrong"
fi

# Test PostgreSQL connection
echo "[INIT] Testing PostgreSQL connection..."
if PGPASSWORD="$POSTGRES_PASSWORD" pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; then
  echo "[INIT] PostgreSQL connection OK"
else
  echo "[WARN] PostgreSQL not reachable yet — backup will retry on schedule"
fi

# Export all env vars for cron (cron runs in a clean environment)
env | grep -E '^(POSTGRES_|S3_|BACKUP_|TZ=)' > /app/.env.backup
echo "PATH=$PATH" >> /app/.env.backup

# Write crontab
echo "$CRON_EXPR /bin/bash -c 'source /app/.env.backup && /app/backup.sh >> /proc/1/fd/1 2>&1'" > /var/spool/cron/crontabs/root
chmod 0600 /var/spool/cron/crontabs/root

echo "[INIT] Cron scheduled: $CRON_EXPR"
echo "[INIT] Waiting for first scheduled backup..."
echo "========================================"

# Run initial backup if requested
if [ "${BACKUP_ON_START:-false}" = "true" ]; then
  echo "[INIT] Running initial backup..."
  /app/backup.sh
fi

# Start cron in foreground
exec crond -f -l 2
