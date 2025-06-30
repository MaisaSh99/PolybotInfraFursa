#######################################
# Region and Networking               #
#######################################
variable "region" {
  description = "AWS region"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to deploy resources in"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block for the new VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

#######################################
# Access and Naming                   #
#######################################
variable "key_pair_name" {
  description = "Name of the EC2 key pair to use for SSH access"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "polybot-k8s"
}

variable "ami_id" {
  description = "AMI ID to use for both control-plane and worker instances"
  type        = string
}

#######################################
# Control Plane & Worker Instances    #
#######################################
variable "instance_type_control_plane" {
  description = "EC2 instance type for the control plane node"
  type        = string
  default     = "t2.medium"
}

variable "instance_type_worker" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t2.small"
}

#######################################
# Auto Scaling for Worker Nodes       #
#######################################
variable "min_worker_nodes" {
  description = "Minimum number of worker nodes in the ASG"
  type        = number
  default     = 1
}

variable "max_worker_nodes" {
  description = "Maximum number of worker nodes in the ASG"
  type        = number
  default     = 3
}

variable "desired_worker_nodes" {
  description = "Desired number of worker nodes in the ASG"
  type        = number
  default     = 2
}

#######################################
# Existing VPC Support                #
#######################################
variable "use_existing_vpc" {
  description = "Whether to use an existing VPC"
  type        = bool
  default     = false
}

variable "existing_vpc_name" {
  description = "Name of the existing VPC to use (if enabled)"
  type        = string
  default     = ""
}

variable "public_subnet_ids" {
  description = "List of existing public subnet IDs to use (when use_existing_vpc is true)"
  type        = list(string)
  default     = []
}