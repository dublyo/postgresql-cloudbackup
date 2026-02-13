#!/bin/bash
set -euo pipefail

# ============================================
# PostgreSQL Cloud Backup — Backup Script
# Dumps PostgreSQL, compresses, uploads to S3,
# enforces retention policy
# ============================================

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${POSTGRES_DB}-${TIMESTAMP}.sql.gz"
TEMP_DIR="/tmp/backups"
TEMP_PATH="${TEMP_DIR}/${BACKUP_FILE}"
S3_PATH_PREFIX="${S3_PATH_PREFIX:-backups/}"
BACKUP_RETENTION="${BACKUP_RETENTION:-3}"

# Ensure temp dir exists
mkdir -p "$TEMP_DIR"

echo "========================================"
echo "[BACKUP] Starting at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "[BACKUP] Database: ${POSTGRES_DB}"
echo "[BACKUP] File: ${BACKUP_FILE}"
echo "========================================"

# ----------------------------------------
# Step 1: pg_dump + gzip
# ----------------------------------------
echo "[STEP 1/3] Dumping database..."

DUMP_START=$(date +%s)

PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  -h "$POSTGRES_HOST" \
  -p "${POSTGRES_PORT:-5432}" \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --no-owner \
  --no-acl \
  --clean \
  --if-exists \
  --format=plain \
  | gzip -9 > "$TEMP_PATH"

DUMP_END=$(date +%s)
DUMP_DURATION=$((DUMP_END - DUMP_START))
FILE_SIZE=$(du -h "$TEMP_PATH" | cut -f1)

echo "[STEP 1/3] Dump complete: ${FILE_SIZE} in ${DUMP_DURATION}s"

# ----------------------------------------
# Step 2: Upload to S3
# ----------------------------------------
echo "[STEP 2/3] Uploading to S3..."

S3_KEY="${S3_PATH_PREFIX}${BACKUP_FILE}"
UPLOAD_START=$(date +%s)

aws s3 cp "$TEMP_PATH" "s3://${S3_BUCKET}/${S3_KEY}" \
  --endpoint-url "$S3_ENDPOINT" \
  --no-progress \
  --content-type "application/gzip" \
  --metadata "database=${POSTGRES_DB},timestamp=${TIMESTAMP},host=${POSTGRES_HOST}"

UPLOAD_END=$(date +%s)
UPLOAD_DURATION=$((UPLOAD_END - UPLOAD_START))

echo "[STEP 2/3] Upload complete in ${UPLOAD_DURATION}s → s3://${S3_BUCKET}/${S3_KEY}"

# Clean up temp file
rm -f "$TEMP_PATH"

# ----------------------------------------
# Step 3: Retention — delete oldest backups
# ----------------------------------------
echo "[STEP 3/3] Applying retention (keep ${BACKUP_RETENTION})..."

# List all backups for this database, sorted by name (which includes timestamp)
BACKUP_LIST=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PATH_PREFIX}" \
  --endpoint-url "$S3_ENDPOINT" \
  2>/dev/null \
  | grep "${POSTGRES_DB}-" \
  | grep "\.sql\.gz$" \
  | awk '{print $NF}' \
  | sort)

BACKUP_COUNT=$(echo "$BACKUP_LIST" | grep -c . || true)

if [ "$BACKUP_COUNT" -gt "$BACKUP_RETENTION" ]; then
  DELETE_COUNT=$((BACKUP_COUNT - BACKUP_RETENTION))
  echo "[STEP 3/3] Found ${BACKUP_COUNT} backups, deleting ${DELETE_COUNT} oldest..."

  echo "$BACKUP_LIST" | head -n "$DELETE_COUNT" | while read -r OLD_BACKUP; do
    echo "[STEP 3/3] Deleting: ${OLD_BACKUP}"
    aws s3 rm "s3://${S3_BUCKET}/${S3_PATH_PREFIX}${OLD_BACKUP}" \
      --endpoint-url "$S3_ENDPOINT" \
      2>/dev/null || echo "[WARN] Failed to delete ${OLD_BACKUP}"
  done
else
  echo "[STEP 3/3] ${BACKUP_COUNT}/${BACKUP_RETENTION} backups stored, no cleanup needed"
fi

# ----------------------------------------
# Done
# ----------------------------------------
TOTAL_DURATION=$(($(date +%s) - DUMP_START))
echo "========================================"
echo "[BACKUP] Completed in ${TOTAL_DURATION}s"
echo "[BACKUP] File: ${BACKUP_FILE} (${FILE_SIZE})"
echo "[BACKUP] Location: s3://${S3_BUCKET}/${S3_KEY}"
echo "[BACKUP] Next backup on schedule"
echo "========================================"
