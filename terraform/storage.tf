resource "aws_s3_bucket" "mail" {
  bucket = "${var.name_prefix}-mail-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_public_access_block" "mail" {
  bucket                  = aws_s3_bucket.mail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mail" {
  bucket = aws_s3_bucket.mail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SES inbound can't write to a KMS-encrypted bucket without extra key policy
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "mail" {
  bucket = aws_s3_bucket.mail.id
  rule {
    id     = "expire-processed"
    status = "Enabled"
    filter { prefix = "processed/" }
    expiration { days = 90 }
  }
}

resource "aws_s3_bucket_policy" "mail_ses_write" {
  bucket = aws_s3_bucket.mail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSESPuts"
      Effect    = "Allow"
      Principal = { Service = "ses.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.mail.arn}/inbox/*"
      Condition = {
        StringEquals = { "AWS:SourceAccount" = data.aws_caller_identity.current.account_id }
        # Trust rules in the local set and the shared set (migration). ArnLike over a list is OR.
        ArnLike = { "AWS:SourceArn" = [
          for rs in ["${var.name_prefix}-rules", var.shared_rule_set_name] :
          "arn:aws:ses:${var.region}:${data.aws_caller_identity.current.account_id}:receipt-rule-set/${rs}:receipt-rule/*"
        ] }
      }
    }]
  })
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-intake-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "intake" {
  name                       = "${var.name_prefix}-intake-queue"
  visibility_timeout_seconds = 120
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue_policy" "intake_from_s3" {
  queue_url = aws_sqs_queue.intake.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.intake.arn
      Condition = {
        ArnEquals    = { "aws:SourceArn" = aws_s3_bucket.mail.arn }
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_s3_bucket_notification" "inbox_to_sqs" {
  bucket = aws_s3_bucket.mail.id

  queue {
    queue_arn     = aws_sqs_queue.intake.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "inbox/"
  }

  depends_on = [aws_sqs_queue_policy.intake_from_s3]
}
