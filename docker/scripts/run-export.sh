#!/bin/bash
set -euo pipefail

echo "=== BE Historic Export Starting ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "S3 Bucket: ${EXPORT_S3_BUCKET}"

export OUTPUT_DIR="/tmp/exports"
mkdir -p "${OUTPUT_DIR}"

echo "Running RSS export (CSV)..."
bash /app/export_rss_csv.sh

echo "Running MRSS export (XLSX)..."
bash /app/export_mrss_xlsx.sh

S3_PREFIX="${S3_PREFIX:-exports/$(date +%Y-%m-%d_%H%M%S)}"
echo "Uploading results to s3://${EXPORT_S3_BUCKET}/${S3_PREFIX}/"

aws s3 sync "/tmp/" "s3://${EXPORT_S3_BUCKET}/${S3_PREFIX}/" \
    --exclude "*" \
    --include "*_combined.txt" \
    --include "*.csv" \
    --include "*.xlsx" \
    --include "*.xml" \
    --only-show-errors

echo "=== Export Complete ==="
echo "Results: s3://${EXPORT_S3_BUCKET}/${S3_PREFIX}/"