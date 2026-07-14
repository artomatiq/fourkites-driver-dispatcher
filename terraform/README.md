# Terraform — FourKites Driver Dispatcher

Infrastructure for the pipeline in [../ARCHITECTURE.md](../ARCHITECTURE.md):
SES → S3 → SQS → a `t4g.nano` worker whose Elastic IP is the static FourKites egress.

## Files

| File | Contents |
|------|----------|
| `bootstrap/` | S3 state bucket + DynamoDB lock table (local state) |
| `providers.tf` | Provider + S3 backend |
| `variables.tf` / `terraform.tfvars.example` | Inputs |
| `network.tf` | VPC, public subnet, IGW, security group |
| `storage.tf` | Mail bucket, SQS queue + DLQ, S3→SQS notification |
| `ses.tf` | Domain identity, DKIM, receipt rule → S3 |
| `secrets.tf` | FourKites config + phonebook in SSM |
| `iam.tf` | Instance role + profile |
| `compute.tf` | EC2 instance, EIP, worker upload, user_data |
| `worker/` | Python worker |

## Apply

`bootstrap/` runs once (local state), then the root stack (S3 backend).

FourKites issues the API key only after its Elastic IP is allowlisted, so the key/URL
are empty on the first apply and set on a second. `fourkites_api_key` / `fourkites_api_url`
default empty; the worker re-reads SSM per message, so the second apply needs no restart.

## Manual steps (not in Terraform)

- DNS records from `terraform output dns_records_to_add`, added at Squarespace.
- Elastic IP (`terraform output elastic_ip`) registered with FourKites.
- SES domain verification + production access.
- Bedrock model access for Claude Haiku 4.5.

## Notes

- Access is via SSM Session Manager; set `ssh_key_name` + `ssh_ingress_cidr` for SSH.
- `assign_driver` payload/header field names in `worker/worker.py` are unconfirmed
  (FourKites case 02933735).
- Driver phone numbers live only in the gitignored `terraform.auto.tfvars` → SSM.
