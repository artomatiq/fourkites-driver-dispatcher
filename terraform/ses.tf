resource "aws_ses_domain_identity" "mail" {
  domain = var.mail_domain
}

resource "aws_ses_domain_dkim" "mail" {
  domain = aws_ses_domain_identity.mail.domain
}

# Inbound mail lands in the shared receipt rule set (ccs-bot-rules), which is owned
# and activated elsewhere — this repo manages ONLY its own rule inside that set, and
# does not touch the set itself or which set is active.
resource "aws_ses_receipt_rule" "intake_to_s3" {
  name          = "${var.name_prefix}-intake-to-s3"
  rule_set_name = var.shared_rule_set_name
  # Single intake address. The bot sends From auto@ but stamps Reply-To: dispatch@, so
  # human replies come back here — auto@ is send-only and doesn't need to receive.
  recipients    = ["${var.intake_local_part}@${var.mail_domain}"]
  enabled       = true
  scan_enabled  = true

  s3_action {
    bucket_name       = aws_s3_bucket.mail.id
    object_key_prefix = "inbox/"
    position          = 1
  }

  depends_on = [aws_s3_bucket_policy.mail_ses_write]
}
