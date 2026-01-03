#!/bin/bash
set -euo pipefail

# =============================
# CONFIG
# =============================
TARGET_STORAGE="stgbackuppoc2f2ea852"
TARGET_CONTAINER="vm-disk-backups"

S3_REMOTE="s3:s3-poc-disk-backup"
BACKUP_PREFIX="backup-20251230-063727"  # existing folder/prefix in blob

echo "=== Azure Blob → S3 DR copy ==="
echo "Storage Account: $TARGET_STORAGE"
echo "Container: $TARGET_CONTAINER"
echo "S3 Remote: $S3_REMOTE"
echo "Prefix: $BACKUP_PREFIX"
echo ""

# =============================
# PRECHECK
# =============================
STORAGE_KEY=$(az storage account keys list \
  --account-name "$TARGET_STORAGE" \
  --query "[0].value" -o tsv)

command -v rclone >/dev/null || { echo "❌ rclone not installed"; exit 1; }

# =============================
# LIST BLOBS
# =============================
BLOBS=$(az storage blob list \
  --account-name "$TARGET_STORAGE" \
  --account-key "$STORAGE_KEY" \
  --container-name "$TARGET_CONTAINER" \
  --prefix "$BACKUP_PREFIX" \
  --query "[].name" -o tsv)

if [ -z "$BLOBS" ]; then
  echo "❌ No blobs found for prefix $BACKUP_PREFIX"
  exit 1
fi

echo "Found $(echo "$BLOBS" | wc -w) blobs to copy"
echo ""

# =============================
# COPY TO S3
# =============================
for BLOB in $BLOBS; do
  echo "Streaming blob → S3: $BLOB"
  rclone copy \
    blob:$TARGET_CONTAINER/$BLOB \
    $S3_REMOTE/$BACKUP_PREFIX/ \
    --progress \
    --transfers 4 \
    --buffer-size 64M \
    --ignore-size
  echo "✓ $BLOB copied to S3"
done

echo ""
echo "✅ All blobs copied to S3"
