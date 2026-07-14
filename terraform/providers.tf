terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Backend created by ./bootstrap. Keep names in sync with bootstrap/main.tf.
  backend "s3" {
    bucket         = "fourkites-dispatch-tfstate"
    key            = "fourkites-dispatch/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "fourkites-dispatch-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "fourkites-driver-dispatcher"
      ManagedBy = "terraform"
      Owner     = "carolinascourier"
    }
  }
}
