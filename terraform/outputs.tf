output "elastic_ip" {
  description = "Static egress IP; register with FourKites."
  value       = aws_eip.worker.public_ip
}

output "intake_address" {
  description = "Address that receives forwarded load emails."
  value       = "${var.intake_local_part}@${var.mail_domain}"
}

output "instance_id" {
  value = aws_instance.worker.id
}

output "mail_bucket" {
  value = aws_s3_bucket.mail.id
}

output "intake_queue_url" {
  value = aws_sqs_queue.intake.id
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.id
}

output "dns_records_to_add" {
  description = "DNS records to add at Squarespace (SES verification, DKIM, inbound MX)."
  value = {
    verification_txt = {
      name  = "_amazonses.${var.mail_domain}"
      type  = "TXT"
      value = aws_ses_domain_identity.mail.verification_token
    }
    dkim_cnames = [for t in aws_ses_domain_dkim.mail.dkim_tokens : {
      name  = "${t}._domainkey.${var.mail_domain}"
      type  = "CNAME"
      value = "${t}.dkim.amazonses.com"
    }]
    mx = {
      name  = var.mail_domain
      type  = "MX"
      value = "10 inbound-smtp.${var.region}.amazonaws.com"
    }
  }
}
