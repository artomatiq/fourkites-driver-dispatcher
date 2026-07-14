locals {
  ssm_prefix = "/fourkites"
}

resource "aws_ssm_parameter" "api_key" {
  name  = "${local.ssm_prefix}/api_key"
  type  = "SecureString"
  value = var.fourkites_api_key == "" ? "PENDING" : var.fourkites_api_key
}

resource "aws_ssm_parameter" "auth_header" {
  name  = "${local.ssm_prefix}/auth_header"
  type  = "String"
  value = var.fourkites_auth_header
}

resource "aws_ssm_parameter" "api_url" {
  name  = "${local.ssm_prefix}/api_url"
  type  = "String"
  value = var.fourkites_api_url == "" ? "PENDING" : var.fourkites_api_url
}

resource "aws_ssm_parameter" "company_id" {
  name  = "${local.ssm_prefix}/company_id"
  type  = "String"
  value = var.fourkites_company_id == "" ? "-" : var.fourkites_company_id
}

resource "aws_ssm_parameter" "carrier_scac" {
  name  = "${local.ssm_prefix}/carrier_scac"
  type  = "String"
  value = var.carrier_scac
}

resource "aws_ssm_parameter" "phonebook" {
  name  = "${local.ssm_prefix}/phonebook"
  type  = "SecureString"
  value = jsonencode(var.driver_phonebook)
}
