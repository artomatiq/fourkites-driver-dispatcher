resource "aws_s3_object" "worker_code" {
  bucket = aws_s3_bucket.mail.id
  key    = "deploy/worker.py"
  source = "${path.module}/worker/worker.py"
  etag   = filemd5("${path.module}/worker/worker.py")
}

resource "aws_s3_object" "worker_requirements" {
  bucket = aws_s3_bucket.mail.id
  key    = "deploy/requirements.txt"
  source = "${path.module}/worker/requirements.txt"
  etag   = filemd5("${path.module}/worker/requirements.txt")
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region           = var.region
    queue_url        = aws_sqs_queue.intake.id
    mail_bucket      = aws_s3_bucket.mail.id
    reply_from       = var.admin_reply_from
    reply_to         = "${var.intake_local_part}@${var.mail_domain}"
    bedrock_model_id = var.bedrock_model_id
    ssm_prefix       = local.ssm_prefix
  })
}

resource "aws_instance" "worker" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.worker.id]
  iam_instance_profile   = aws_iam_instance_profile.worker.name
  key_name               = var.ssh_key_name != "" ? var.ssh_key_name : null

  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  depends_on = [
    aws_s3_object.worker_code,
    aws_s3_object.worker_requirements,
    aws_ssm_parameter.api_key,
    aws_ssm_parameter.api_url,
    aws_ssm_parameter.phonebook,
  ]

  tags = { Name = "${var.name_prefix}-worker" }
}

resource "aws_eip" "worker" {
  domain   = "vpc"
  instance = aws_instance.worker.id
  tags     = { Name = "${var.name_prefix}-eip" }

  depends_on = [aws_internet_gateway.main]
}
