#!/bin/bash
set -euo pipefail

# ==================================================
# Azure Managed Disk Backup Script
# - Creates snapshots of all disks in a resource group
# - Copies snapshots to Azure Blob Storage
# - Optionally replicates backup to S3-compatible storage
# ==================================================

# =============================
# CONFIGURATION
# =============================
SOURCE_RG="rg-vm-backup-poc"
TARGET_STORAGE="stgbackuppoc2f2ea852"
TARGET_CONTAINER="vm-disk-backups"

# Backup identifier (timestamp-based)
BACKUP_PREFIX="backup-$(date +%Y%m%d-%H%M%S)"

# Snapshot SAS expiration (in seconds)
SNAPSHOT_TTL=7200

# Optional disaster recovery copy to S3
ENABLE_S3=true   # true / false
S3_REMOTE="s3:s3-poc-disk-backup"

echo "======================================"
echo "Azure Managed Disk Backup Process"
echo "======================================"
echo "Source Resource Group : $SOURCE_RG"
echo "Target Storage Account: $TARGET_STORAGE"
echo "Target Container      : $TARGET_CONTAINER"
echo "Backup Identifier     : $BACKUP_PREFIX"
echo ""

# =============================
# PRE-CHECKS
# =============================

# Validate Azure CLI authentication
az account show >/dev/null

SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Retrieve Storage Account access key
STORAGE_KEY=$(az storage account keys list \
  --account-name "$TARGET_STORAGE" \
  --query "[0].value" \
  -o tsv)

if [ -z "$STORAGE_KEY" ]; then
  echo "Failed to retrieve Storage Account access key"
  exit 1
fi

# Ensure backup container exists
az storage container create \
  --name "$TARGET_CONTAINER" \
  --account-name "$TARGET_STORAGE" \
  --account-key "$STORAGE_KEY" \
  --public-access off >/dev/null

# =============================
# DISCOVER MANAGED DISKS
# =============================
DISKS=$(az disk list \
  --resource-group "$SOURCE_RG" \
  --query "[].name" -o tsv)

DISK_COUNT=$(echo "$DISKS" | wc -w)

echo "Discovered $DISK_COUNT managed disks"
echo ""

SUCCESS=0
FAILED=0
SNAPSHOTS=()

# =============================
# BACKUP EXECUTION
# =============================
for DISK in $DISKS; do
  echo "--------------------------------------"
  echo "Processing disk: $DISK"

  SNAPSHOT_NAME="${BACKUP_PREFIX}-${DISK}"
  SNAPSHOT_NAME="${SNAPSHOT_NAME:0:80}"

  echo "Creating snapshot: $SNAPSHOT_NAME"

  az snapshot create \
    --resource-group "$SOURCE_RG" \
    --name "$SNAPSHOT_NAME" \
    --source "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$SOURCE_RG/providers/Microsoft.Compute/disks/$DISK" \
    --sku Standard_LRS \
    --incremental false \
    --tags backup=true type=crash-consistent source_disk="$DISK" \
    >/dev/null

  SNAPSHOTS+=("$SNAPSHOT_NAME")
  echo "✓ Snapshot successfully created"

  SNAPSHOT_URI=$(az snapshot grant-access \
    --resource-group "$SOURCE_RG" \
    --name "$SNAPSHOT_NAME" \
    --duration-in-seconds "$SNAPSHOT_TTL" \
    --access-level Read \
    --query accessSAS -o tsv)

  if [ -z "$SNAPSHOT_URI" ]; then
    echo "Failed to generate snapshot SAS URI"
    FAILED=$((FAILED+1))
    continue
  fi

  BLOB_NAME="${BACKUP_PREFIX}-${DISK}.vhd"
  BLOB_NAME=$(echo "$BLOB_NAME" | sed 's/[^a-zA-Z0-9._-]/-/g')

  echo "Initiating snapshot export to Blob Storage"
  echo "Destination blob: $BLOB_NAME"

  az storage blob copy start \
    --account-name "$TARGET_STORAGE" \
    --account-key "$STORAGE_KEY" \
    --destination-container "$TARGET_CONTAINER" \
    --destination-blob "$BLOB_NAME" \
    --source-uri "$SNAPSHOT_URI" \
    >/dev/null

  echo "Blob copy operation started"
  SUCCESS=$((SUCCESS+1))
  sleep 2
done

# =============================
# OPTIONAL S3 DISASTER RECOVERY
# =============================
if [ "$ENABLE_S3" = true ]; then
  echo ""
  echo "S3 disaster recovery replication enabled"
  echo "Waiting for Azure Blob copy to complete..."

  while true; do
    STATUS=$(az storage blob show \
      --account-name "$TARGET_STORAGE" \
      --account-key "$STORAGE_KEY" \
      --container-name "$TARGET_CONTAINER" \
      --name "$BLOB_NAME" \
      --query properties.copy.status \
      -o tsv)

    echo "  Current blob copy status: $STATUS"

    if [ "$STATUS" = "success" ]; then
      echo "Blob copy completed successfully"
      break
    elif [ "$STATUS" = "failed" ]; then
      echo "Blob copy failed"
      FAILED=$((FAILED+1))
      continue 2
    fi

    sleep 20
  done

  S3_OBJECT="$S3_REMOTE/$BACKUP_PREFIX/$BLOB_NAME"

  echo "Replicating backup to S3 destination"
  echo "Target object: $S3_OBJECT"

  rclone copy \
    blob:$TARGET_CONTAINER/$BLOB_NAME \
    "$S3_OBJECT" \
    --progress \
    --transfers 3 \
    --buffer-size 64M \
    --ignore-size

  echo "S3 replication completed"
else
  echo ""
  echo "S3 disaster recovery replication disabled — skipping"
fi

# =============================
# BACKUP SUMMARY
# =============================
echo ""
echo "======================================"
echo "BACKUP EXECUTION SUMMARY"
echo "======================================"
echo "Total disks processed : $DISK_COUNT"
echo "Successful backups    : $SUCCESS"
echo "Failed operations     : $FAILED"
echo "Backup identifier     : $BACKUP_PREFIX"
echo ""
