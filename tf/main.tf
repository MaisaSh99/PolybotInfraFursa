# tf/main.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "maisa-tf-state-ohio"
    key    = "k8s/terraform.tfstate"
    region = "us-east-2"
    encrypt = true
  }
}

provider "aws" {
  region = var.region
}

module "k8s_cluster" {
  source = "./modules/k8s-cluster"
  
  # Global
  region             = var.region
  availability_zones = var.availability_zones
  key_pair_name      = var.key_pair_name
  cluster_name       = var.cluster_name
  ami_id             = var.ami_id
  vpc_cidr           = var.vpc_cidr
  
  # Instance types
  instance_type_control_plane = var.instance_type_control_plane
  instance_type_worker        = var.instance_type_worker
  
  # Worker scaling
  min_worker_nodes     = var.min_worker_nodes
  max_worker_nodes     = var.max_worker_nodes
  desired_worker_nodes = var.desired_worker_nodes
}