resource "aws_ses_domain_identity" "mail" {
  domain = var.mail_domain
}

resource "aws_ses_domain_dkim" "mail" {
  domain = aws_ses_domain_identity.mail.domain
}

resource "aws_ses_receipt_rule_set" "main" {
  rule_set_name = "${var.name_prefix}-rules"
}

resource "aws_ses_active_receipt_rule_set" "main" {
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
}

resource "aws_ses_receipt_rule" "intake_to_s3" {
  name          = "${var.name_prefix}-intake-to-s3"
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
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
