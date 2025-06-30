# tf/variables.tf
#########################
#  Global / Location    #
#########################
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

#########################
#  Access & Naming      #
#########################
variable "key_pair_name" {
  description = "Name of the EC2 Key Pair"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "polybot-k8s"
}

#########################
#  AMI                  #
#########################
variable "ami_id" {
  description = "AMI ID to use for both control-plane and worker nodes"
  type        = string
}

#########################
#  Instance sizes       #
#########################
variable "instance_type_control_plane" {
  description = "EC2 instance type for the control-plane node"
  type        = string
  default     = "t2.medium"
}

variable "instance_type_worker" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t2.small"
}

#########################
#  Control-plane scaling#
#########################
variable "min_control_plane_nodes" {
  description = "Minimum number of control-plane nodes"
  type        = number
  default     = 1
}

variable "max_control_plane_nodes" {
  description = "Maximum number of control-plane nodes"
  type        = number
  default     = 1
}

variable "desired_control_plane_nodes" {
  description = "Desired number of control-plane nodes"
  type        = number
  default     = 1
}

#########################
#  Worker scaling       #
#########################
variable "min_worker_nodes" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "max_worker_nodes" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "desired_worker_nodes" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

#########################
#  VPC & Subnets        #
#########################
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
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

variable "use_existing_vpc" {
  description = "Whether to use an existing VPC"
  type        = bool
  default     = false
}

variable "existing_vpc_name" {
  description = "Name of the existing VPC to use (if any)"
  type        = string
  default     = ""
}
