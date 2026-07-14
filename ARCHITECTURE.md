# FourKites Driver Dispatcher — Architecture

Internal automation for Carolinas Courier that assigns a driver's phone number to a
load in FourKites, triggered by a forwarded email.

## Overview

An admin forwards a load email (with the load's TMS ID and the driver's name or phone)
to the intake address. The system parses it, resolves the driver's phone, calls the
FourKites **Assignment Update API** to set that phone as the tracking asset, and emails
the status back. FourKites tracks the **phone number** as the asset, so a phone is always
required; a forwarded name is resolved via a small phonebook (a handful of drivers).

## End-to-end flow

```
Admin forwards load email
        │
        ▼
dispatch@bot.carolinascourier.com
        │  (MX record → SES inbound)
        ▼
┌─────────────────┐
│  SES receipt    │  writes raw MIME (.eml) to S3
│  rule           │
└────────┬────────┘
         ▼
   S3 bucket  (inbox/ prefix)
         │  s3:ObjectCreated event
         ▼
   SQS queue  ────────────► SQS dead-letter queue (maxReceiveCount ~3)
         │  message = pointer { bucket, key }, NOT the email body
         ▼
┌────────────────────────────────────────────┐
│  EC2  t4g.nano  +  Elastic IP (attached)    │
│  (long-polls SQS)                            │
│                                              │
│  1. s3:GetObject  → fetch raw .eml           │
│  2. parse MIME (stdlib email module)          │
│  3. Bedrock: Claude Haiku 4.5 extracts        │
│       { tmsId, driverName, driverPhone? }     │
│  4. resolve phone: extracted phone, else      │
│       look up name in SSM phonebook           │
│  5. POST FourKites Assignment Update API      │
│       (egresses from the Elastic IP) ✅       │
│  6. ses:SendEmail → reply to admin            │
│  7. move S3 object inbox/ → processed/        │
│  8. sqs:DeleteMessage                         │
│                                              │
│  Unresolved phone → reply asking for it.      │
│  Failure → leave SQS message → retry → DLQ.   │
└────────────────────────────────────────────┘
```

## Components

| Resource | Purpose |
|----------|---------|
| **DNS** (`bot.carolinascourier.com`) | MX → SES inbound; TXT + DKIM for verification |
| **SES receipt rule** | `dispatch@bot.carolinascourier.com` → raw MIME to S3 |
| **S3 bucket** | `inbox/` and `processed/` prefixes |
| **S3 event notification** | `s3:ObjectCreated:*` under `inbox/` → SQS (no SNS) |
| **SQS queue + DLQ** | Durable work list with retry / dead-letter |
| **EC2** (`t4g.nano`, AL2023, public subnet) | Runs the worker |
| **Elastic IP** | The single static IP registered with FourKites |
| **IAM role** | Least-privilege: SQS, S3, SES, Bedrock, SSM |

## Key design decisions

**EC2, not Lambda.** FourKites allowlists the API key to a single static outbound IP.
Every way to get a stable egress IP on AWS needs an always-on component (NAT or an EIP-
bearing instance), so one small EC2 that both runs the logic and owns the Elastic IP is
simpler and cheaper than Lambda + NAT + VPC wiring.

**Elastic IP** is attached to the instance, so its outbound call egresses from that fixed
address — no NAT. (A Lambda can't own an EIP; EC2 can.)

**SQS, no SNS.** One consumer, so SNS fan-out adds nothing; S3 sends `ObjectCreated`
straight to SQS. SQS gives durability — mail waits if the box is down, and repeated
failures fall to the DLQ instead of being lost.

**`t4g.nano`** is enough — the LLM runs in Bedrock, not on the box; the instance only does
I/O on one email at a time.

**Claude Haiku 4.5 via Bedrock** — IAM-authorized (no API key on the box), billed through
AWS. Haiku is a strong, cheap extractor for the core task: pulling structured fields from
inconsistently-formatted emails. Bedrock model access must be enabled once in the console.

**Phonebook in SSM.** Driver phone numbers are PII and stay out of git: the
`driver_phonebook` variable (set in the gitignored `terraform.auto.tfvars`) is written to
an SSM SecureString (`/fourkites/phonebook`) that the worker reads. Editing the roster is a
`terraform apply` — no code change.

## Authentication (FourKites)

- **API key** from the FourKites Developer Portal (not OAuth2 — that needs backend
  enablement; the API-key path is self-service).
- **API:** Assignment Update — https://docs.fourkites.com/api-reference/assignment-update
- **IP allowlist:** the Elastic IP.
- Exact endpoint, auth header, and request field names are unconfirmed (case 02933735).

## Cost estimate

~$7–10/mo: EC2 `t4g.nano` (~$3) + Elastic IP (~$3.60); Bedrock and S3/SQS/SES negligible.

## Prerequisites

1. DNS control of `bot.carolinascourier.com` (MX + SES records).
2. SES production access (sandbox only emails verified addresses).
3. Confirmed FourKites Assignment Update schema (case 02933735).
