## rclone Setup (Azure Blob → S3)

1. **Install rclone**:

```bash
# Linux/macOS
curl https://rclone.org/install.sh | sudo bash
# Windows: download from https://rclone.org/downloads/
```

2. **Configure Azure Blob remote**:

```bash
rclone config
```

* `n` → New remote → name: `blob`
* Storage type: `Azure Blob Storage`
* Account name: your `TARGET_STORAGE`
* Account key: `az storage account keys list --account-name $TARGET_STORAGE --query "[0].value" -o tsv`
* Leave endpoint as default (`core.windows.net`)
* Save and exit

3. **Configure S3 remote**:

```bash
rclone config
```

* `n` → New remote → name: `s3`
* Storage type: `S3`
* Fill in `Access Key`, `Secret Key`, `Region`, and optional endpoint (for AWS or compatible S3)
* Save and exit

4. **Test remotes**:

```bash
rclone ls blob:$TARGET_CONTAINER
rclone ls s3:my-bucket
```

5. **Copy Blob → S3** (used in script):

```bash
rclone copy \
    blob:$TARGET_CONTAINER/$BLOB_NAME \
    s3:$BACKUP_PREFIX/$BLOB_NAME \
    --progress \
    --transfers 4 \
    --buffer-size 64M \
    --ignore-size
```