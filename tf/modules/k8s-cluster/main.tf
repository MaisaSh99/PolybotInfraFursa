# tf/modules/k8s-cluster/main.tf

# Data source to get existing VPC by name
data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  filter {
    name   = "tag:Name"
    values = [var.existing_vpc_name]
  }
}

# Data source to fetch existing subnets by IDs (only if subnet IDs are provided)
data "aws_subnet" "existing" {
  count = var.use_existing_vpc && length(var.public_subnet_ids) > 0 ? length(var.public_subnet_ids) : 0
  id    = var.public_subnet_ids[count.index]
}

# Create new VPC only if not using existing one
resource "aws_vpc" "k8s_vpc" {
  count      = var.use_existing_vpc ? 0 : 1
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# Create internet gateway only if creating new VPC
resource "aws_internet_gateway" "igw" {
  count  = var.use_existing_vpc ? 0 : 1
  vpc_id = aws_vpc.k8s_vpc[0].id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# Local values to determine which VPC and subnets to use
locals {
  vpc_id     = var.use_existing_vpc ? data.aws_vpc.existing[0].id : aws_vpc.k8s_vpc[0].id
  # Use existing subnet IDs if provided, otherwise use created subnets
  subnet_ids = length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : aws_subnet.public_subnets[*].id
  # Use the provided VPC CIDR
  vpc_cidr   = var.vpc_cidr
}

# IAM Role for control plane EC2 instance
resource "aws_iam_role" "control_plane_role" {
  name = "${var.cluster_name}-control-plane-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach necessary policies to the control plane IAM role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "secrets_manager_access" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

# Instance profile for EC2
resource "aws_iam_instance_profile" "control_plane_profile" {
  name = "${var.cluster_name}-control-plane-profile"
  role = aws_iam_role.control_plane_role.name
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.cluster_name}-worker-profile"
  role = aws_iam_role.control_plane_role.name
}

# Create new subnets if no existing subnet IDs are provided
resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnet_ids) > 0 ? 0 : 2
  vpc_id                  = local.vpc_id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-subnet-${count.index}"
  }
}

# Get existing route table for existing VPC
data "aws_route_table" "existing_public" {
  count  = var.use_existing_vpc ? 1 : 0
  vpc_id = local.vpc_id
  filter {
    name   = "association.main"
    values = ["false"]
  }
}

# Create route table only if creating new VPC
resource "aws_route_table" "public_rt" {
  count  = var.use_existing_vpc ? 0 : 1
  vpc_id = local.vpc_id

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

# Create route only if creating new VPC
resource "aws_route" "igw_route" {
  count                  = var.use_existing_vpc ? 0 : 1
  route_table_id         = aws_route_table.public_rt[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw[0].id
}

# Create route table associations only if creating new subnets
resource "aws_route_table_association" "public_assoc" {
  count          = length(var.public_subnet_ids) > 0 ? 0 : 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt[0].id
}

# FIXED SECURITY GROUP - Allow port 6443 from anywhere
resource "aws_security_group" "control_plane_sg" {
  name        = "${var.cluster_name}-control-plane-sg"
  description = "Allow SSH, Kubernetes API, and internal VPC traffic"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubernetes API from anywhere (for GitHub Actions)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubernetes API traffic from VPC"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "Allow all TCP traffic within the VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "Allow all UDP traffic within the VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Alternative HTTPS port"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-control-plane-sg"
  }
}

resource "aws_instance" "control_plane" {
  ami                         = var.ami_id
  instance_type               = var.instance_type_control_plane
  subnet_id                   = local.subnet_ids[0]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.control_plane_sg.id]

  user_data = file("${path.module}/user_data_control_plane.sh")
  iam_instance_profile = aws_iam_instance_profile.control_plane_profile.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name = "${var.cluster_name}-control-plane"
  }
}

resource "aws_eip" "control_plane_eip" {
  instance = aws_instance.control_plane.id
  domain   = "vpc"

  tags = {
    Name = "${var.cluster_name}-control-plane-eip"
  }
}

resource "aws_security_group" "worker_sg" {
  name        = "${var.cluster_name}-worker-sg"
  description = "Allow traffic for worker nodes"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow all traffic from within VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-worker-sg"
  }
}

resource "aws_launch_template" "worker_template" {
  name_prefix   = "${var.cluster_name}-worker-"
  image_id      = var.ami_id
  instance_type = var.instance_type_worker

  key_name = var.key_pair_name

  iam_instance_profile {
    name = aws_iam_instance_profile.worker_profile.name
  }

  vpc_security_group_ids = [aws_security_group.worker_sg.id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(file("${path.module}/user_data_worker.sh"))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-worker"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "worker_asg" {
  name                      = "${var.cluster_name}-worker-asg"
  desired_capacity          = var.desired_worker_nodes
  max_size                  = var.max_worker_nodes
  min_size                  = var.min_worker_nodes
  vpc_zone_identifier       = local.subnet_ids
  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.worker_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}