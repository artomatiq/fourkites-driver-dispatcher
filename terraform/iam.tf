data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "worker" {
  name               = "${var.name_prefix}-worker-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

data "aws_iam_policy_document" "worker" {
  statement {
    sid = "Sqs"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [aws_sqs_queue.intake.arn]
  }

  statement {
    sid       = "S3Objects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.mail.arn}/*"]
  }
  statement {
    sid       = "S3List"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.mail.arn]
  }

  statement {
    sid       = "SesSend"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = ["*"]
  }

  statement {
    sid     = "Bedrock"
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/${var.bedrock_model_id}",
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-*",
    ]
  }

  statement {
    sid       = "SsmRead"
    actions   = ["ssm:GetParameter", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "worker" {
  name   = "${var.name_prefix}-worker-policy"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.name_prefix}-worker-profile"
  role = aws_iam_role.worker.name
}
