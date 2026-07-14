variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "fourkites-dispatch"
}

variable "mail_domain" {
  type    = string
  default = "bot.carolinascourier.com"
}

variable "intake_local_part" {
  type    = string
  default = "dispatch"
}

variable "admin_reply_from" {
  type    = string
  default = "auto@bot.carolinascourier.com"
}

variable "instance_type" {
  type    = string
  default = "t4g.nano"
}

variable "ssh_key_name" {
  type        = string
  description = "EC2 key pair for SSH. Empty = SSM Session Manager only."
  default     = ""
}

variable "ssh_ingress_cidr" {
  type        = string
  description = "CIDR allowed to SSH. Empty = no SSH ingress rule."
  default     = ""
}

variable "bedrock_model_id" {
  type    = string
  default = "deepseek.v3.2"
}

variable "max_receive_count" {
  type    = number
  default = 3
}

# FourKites api_key/api_url default empty (set on the second apply, once the Elastic
# IP is allowlisted). Empty is stored as "PENDING" since SSM rejects empty strings.
variable "fourkites_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "fourkites_auth_header" {
  type        = string
  description = "Header the API key is sent in (Authorization / X-API-KEY / apikey)."
  default     = "Authorization"
}

variable "fourkites_api_url" {
  type    = string
  default = ""
}

variable "fourkites_company_id" {
  type    = string
  default = ""
}

variable "carrier_scac" {
  type    = string
  default = "COUB"
}

variable "driver_phonebook" {
  type      = map(string)
  sensitive = true
  default   = {}
}
