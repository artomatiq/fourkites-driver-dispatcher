resource "aws_ses_domain_identity" "mail" {
  domain = var.mail_domain
}

resource "aws_ses_domain_dkim" "mail" {
  domain = aws_ses_domain_identity.mail.domain
}

# The receipt rule SET (fourkites-dispatch-rules) is intentionally NOT managed by
# Terraform — it was `terraform state rm`'d so an apply can't replace/delete it. We
# still manage the rule inside it and which set is active, by referencing it by name.
resource "aws_ses_active_receipt_rule_set" "main" {
  rule_set_name = "${var.name_prefix}-rules"
}

resource "aws_ses_receipt_rule" "intake_to_s3" {
  name          = "${var.name_prefix}-intake-to-s3"
  rule_set_name = "${var.name_prefix}-rules"
  # Accept both the intake address and the bot's reply-from, so a human can reply to
  # the auto-reply and have it loop back into the pipeline.
  recipients    = ["${var.intake_local_part}@${var.mail_domain}", var.admin_reply_from]
  enabled       = true
  scan_enabled  = true

  s3_action {
    bucket_name       = aws_s3_bucket.mail.id
    object_key_prefix = "inbox/"
    position          = 1
  }

  depends_on = [aws_s3_bucket_policy.mail_ses_write]
}
