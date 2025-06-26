terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=5.55"
    }
  }

  required_version = ">= 1.7.0"
}

provider "aws" {
  region  = "us-east-2"
  profile = "default"  # change in case you want to work with another AWS account profile
}

resource "aws_instance" "polybot_app" {
  ami           = "ami-0d1b5a8c13042c939"
  instance_type = "t2.micro"

  tags = {
    Name = "maisa-tf-practice"
  }
}