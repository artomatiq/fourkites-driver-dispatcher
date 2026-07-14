"""FourKites driver-dispatcher worker.

SQS pointer -> S3 .eml -> Bedrock (Converse) field extraction -> phone resolve ->
FourKites Assignment Update -> SES reply -> archive. Config/secrets come from SSM.
"""
from __future__ import annotations

import json
import logging
import os
import re
from email import message_from_bytes
from email.utils import parseaddr

import boto3
import urllib.request
import urllib.error
from urllib.parse import unquote_plus

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("worker")

REGION = os.environ["AWS_REGION"]
QUEUE_URL = os.environ["QUEUE_URL"]
MAIL_BUCKET = os.environ["MAIL_BUCKET"]
REPLY_FROM = os.environ["REPLY_FROM"]
BEDROCK_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
SSM_PREFIX = os.environ["SSM_PREFIX"]

sqs = boto3.client("sqs", region_name=REGION)
s3 = boto3.client("s3", region_name=REGION)
ses = boto3.client("ses", region_name=REGION)
bedrock = boto3.client("bedrock-runtime", region_name=REGION)
ssm = boto3.client("ssm", region_name=REGION)

CFG: dict[str, str] = {}
PHONEBOOK: dict[str, str] = {}


def refresh_config() -> None:
    # Re-read on each message so API-key / phonebook changes apply without a restart.
    global CFG, PHONEBOOK
    resp = ssm.get_parameters_by_path(Path=SSM_PREFIX, Recursive=True, WithDecryption=True)
    CFG = {p["Name"].rsplit("/", 1)[-1]: p["Value"] for p in resp["Parameters"]}
    PHONEBOOK = json.loads(CFG.get("phonebook", "{}"))


def lookup_phone(name: str | None) -> str | None:
    if not name:
        return None
    return PHONEBOOK.get(" ".join(name.strip().lower().split()))


def normalize_phone(raw: str | None) -> str | None:
    if not raw:
        return None
    digits = re.sub(r"[^\d+]", "", raw)
    if digits.startswith("+"):
        return digits
    if len(digits) == 10:
        return "+1" + digits
    if len(digits) == 11 and digits.startswith("1"):
        return "+" + digits
    return None


def extract_body_text(msg) -> str:
    if msg.is_multipart():
        parts = []
        for part in msg.walk():
            if part.get_content_type() == "text/plain" and "attachment" not in str(
                part.get("Content-Disposition", "")
            ):
                payload = part.get_payload(decode=True)
                if payload:
                    parts.append(payload.decode(part.get_content_charset() or "utf-8", "replace"))
        if parts:
            return "\n".join(parts)
    payload = msg.get_payload(decode=True)
    if payload:
        return payload.decode(msg.get_content_charset() or "utf-8", "replace")
    return ""


EXTRACT_PROMPT = """You extract structured fields from a forwarded freight load email.
Return ONLY minified JSON with keys: tmsId (string), driverName (string or null),
driverPhone (string or null), confidence (0-1 number). No prose.

Email:
{body}
"""


def extract_fields(body: str) -> dict:
    resp = bedrock.converse(
        modelId=BEDROCK_MODEL_ID,
        messages=[{"role": "user", "content": [{"text": EXTRACT_PROMPT.format(body=body[:8000])}]}],
        inferenceConfig={"maxTokens": 2048},
    )
    # Concatenate text blocks (reasoning models emit a separate reasoningContent block).
    text = "".join(b.get("text", "") for b in resp["output"]["message"]["content"])
    match = re.search(r"\{.*\}", text, re.DOTALL)
    return json.loads(match.group(0) if match else text)


def _http_json(method: str, url: str, headers: dict, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


def assign_driver(tms_id: str, phone: str) -> dict:
    headers = {
        CFG.get("auth_header", "Authorization"): CFG["api_key"],
        "Content-Type": "application/json",
    }
    payload = {
        "loadNumber": tms_id,
        "driverPhone": phone,
        "carrierScac": CFG.get("carrier_scac", ""),
    }
    if CFG.get("company_id") and CFG["company_id"] != "-":
        payload["companyId"] = CFG["company_id"]
    return _http_json("POST", CFG["api_url"], headers, payload)


def reply(to_addr: str, subject: str, text: str) -> None:
    if not to_addr:
        log.warning("no admin address to reply to")
        return
    ses.send_email(
        Source=REPLY_FROM,
        Destination={"ToAddresses": [to_addr]},
        Message={"Subject": {"Data": subject}, "Body": {"Text": {"Data": text}}},
    )


def process_object(bucket: str, key: str) -> None:
    obj = s3.get_object(Bucket=bucket, Key=key)
    msg = message_from_bytes(obj["Body"].read())
    admin = parseaddr(msg.get("Reply-To") or msg.get("From", ""))[1]

    fields = extract_fields(extract_body_text(msg))
    tms_id = (fields.get("tmsId") or "").strip()
    phone = normalize_phone(fields.get("driverPhone")) or lookup_phone(fields.get("driverName"))

    if not tms_id:
        reply(admin, "Load assignment — could not read load ID",
              "I couldn't find the load/TMS ID in that email. Please resend with the load number.")
        archive(bucket, key)
        return

    if not phone:
        name = fields.get("driverName") or "the driver"
        reply(admin, f"Load {tms_id} — need a phone number",
              f"I couldn't resolve a phone for {name}. Please reply with the driver's phone number.")
        archive(bucket, key)
        return

    result = assign_driver(tms_id, phone)
    status = result.get("status") or result.get("message") or "submitted"
    reply(admin, f"Load {tms_id} — driver assigned",
          f"Assigned {phone} to load {tms_id}.\nFourKites status: {status}")
    archive(bucket, key)


def archive(bucket: str, key: str) -> None:
    new_key = key.replace("inbox/", "processed/", 1)
    s3.copy_object(Bucket=bucket, CopySource={"Bucket": bucket, "Key": key}, Key=new_key)
    s3.delete_object(Bucket=bucket, Key=key)


def handle_message(msg: dict) -> None:
    for record in json.loads(msg["Body"]).get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])
        log.info("processing s3://%s/%s", bucket, key)
        process_object(bucket, key)


def main() -> None:
    log.info("worker up; polling %s", QUEUE_URL)
    while True:
        resp = sqs.receive_message(
            QueueUrl=QUEUE_URL, MaxNumberOfMessages=1, WaitTimeSeconds=20, VisibilityTimeout=120
        )
        for msg in resp.get("Messages", []):
            try:
                refresh_config()
                handle_message(msg)
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=msg["ReceiptHandle"])
            except Exception:
                log.exception("failed to process message; leaving for retry")


if __name__ == "__main__":
    main()
