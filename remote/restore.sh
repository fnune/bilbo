#!/usr/bin/env bash

set -euo pipefail

BUCKET_NAME=$(pulumi stack output bucketName)
DEST_PATH="${2:-./borg-restore}"

temp_config=$(mktemp)
cleanup() {
  rm -f "$temp_config"
}
trap cleanup EXIT

pulumi stack output bucketRcloneConfig --show-secrets >"$temp_config"

initiate_restore() {
  echo "Initiating restore from S3 Glacier for $BUCKET_NAME/mirrored..."
  rclone --config "$temp_config" \
    backend restore aws-glacier:"$BUCKET_NAME"/mirrored \
    -o priority=Standard \
    -o lifetime=7 \
    --progress
  echo "Restore initiated. This will take 12-48 hours to complete. The data will be available to download for 7 days."
}

check_status() {
  echo "Checking restoration status for $BUCKET_NAME/mirrored..."
  rclone --config "$temp_config" \
    backend restore-status aws-glacier:"$BUCKET_NAME"/mirrored
}

download_files() {
  echo "Downloading files from $BUCKET_NAME/mirrored to $DEST_PATH..."
  mkdir -p "$DEST_PATH"
  rclone --config "$temp_config" \
    copy aws-glacier:"$BUCKET_NAME"/mirrored "$DEST_PATH" \
    --progress \
    --stats 30s
  echo "Download complete."
}

case "${1:-help}" in
initiate)
  initiate_restore
  ;;
status)
  check_status
  ;;
download)
  download_files
  ;;
help | *)
  echo "Usage: $0 [initiate|status|download] [destination_path]"
  echo "  initiate - Start the restoration process from Glacier (7-day availability)"
  echo "  status   - Check the status of the restoration"
  echo "  download - Download the restored files (once available)"
  echo "  destination_path - Path where files will be saved (default: ./borg-restore)"
  exit 1
  ;;
esac
