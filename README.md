# BE Historic Data Export — Fargate + S3

## What This Creates

| Resource | Purpose |
|----------|---------|
| **S3 Bucket** | Stores 60-70 GB XML/CSV export data, KMS encrypted, auto-expires after 90 days |
| **S3 Access Logs Bucket** | Logs all access to export data bucket |
| **ECR Repository** | Stores Docker image (immutable tags, scan on push, KMS encrypted) |
| **ECS Cluster + Fargate Task** | Runs export container on demand (2 vCPU, 8GB RAM, 100GB ephemeral disk) |
| **IAM Roles** | Execution role (pull image + logs) + Task role (S3 read/write only) |
| **Security Group** | Outbound only — no inbound needed |
| **CloudWatch Log Group** | Task logs, 365 day retention, KMS encrypted |
| **KMS Key** | Encrypts CloudWatch logs |

## How It Works

```
BE team runs: ./trigger-export.sh (or aws ecs run-task via Console)
    ↓
Fargate spins up container
    ↓
run-export.sh overrides OUTPUT_DIR → runs export.sh
    ↓
export.sh curls RSS feeds → yq converts XML→JSON → export.py → CSV
    ↓
Results uploaded to S3
    ↓
Container shuts down (no idle cost)
```

## Setup Steps

```bash
# 1. Fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit with your VPC ID, subnet IDs, image_tag

# 2. Deploy infrastructure
terraform init
terraform plan
terraform apply

# 3. Copy BE team's scripts into docker/scripts/
#    - export.sh    (from the zip: historic-expo...ipt.zip)
#    - export.py    (from the zip)
#    - sites.txt    (from the zip)

# 4. Build and push Docker image
chmod +x build-and-push.sh trigger-export.sh
./build-and-push.sh v1

# 5. Update trigger-export.sh with your subnet/SG IDs
#    (terraform output will show the values + the full run-task command)

# 6. Run the export
./trigger-export.sh
```

## Monitoring

```bash
# Tail logs in real time
aws logs tail /ecs/be-historic-export --follow

# Check task status
aws ecs list-tasks --cluster be-historic-export-cluster

# List export results in S3
aws s3 ls s3://<bucket-name>/exports/ --recursive
```

## Security Audit (Checkov)

**63 passed / 6 intentionally accepted:**

| Check | Resource | Reason Accepted |
|-------|----------|-----------------|
| CKV_AWS_382 — SG egress 0.0.0.0/0 | fargate_task SG | Required — task curls external RSS feeds |
| CKV2_AWS_62 — S3 event notifications | export_data, access_logs | Not needed — no downstream consumers |
| CKV2_AWS_5 — SG not attached | fargate_task SG | False positive — attached at run-task time via CLI |
| CKV_AWS_144 — S3 cross-region replication | export_data, access_logs | Not needed — temporary export data, no DR requirement |

**Fixed during audit:**
- ECR: immutable tags + KMS encryption
- CloudWatch: 365 day retention + KMS encryption
- S3 lifecycle: abort incomplete multipart uploads
- ECS task: read-only root filesystem with /tmp volume mount
- S3 access logging enabled
- Access logs bucket: versioning + KMS encryption

## Notes

- **No idle cost** — Fargate only runs when triggered, shuts down after completion
- The original script's `OUTPUT_DIR` (hardcoded to a Mac desktop path) is overridden to `/tmp/exports`
- BE team owns the scripts (export.sh, export.py, sites.txt) — infra team owns the Terraform
- ECR tags are immutable — bump version when scripts change: `./build-and-push.sh v2`
- S3 objects auto-expire after 90 days (configurable)
