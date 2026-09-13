terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Local state by default. For anything you want to keep, move to S3 with
  # native locking and uncomment below.
  #
  # backend "s3" {
  #   bucket       = "my-tfstate-bucket"
  #   key          = "homelab/alb-web/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
