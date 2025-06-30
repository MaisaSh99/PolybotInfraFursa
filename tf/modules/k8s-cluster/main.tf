# tf/modules/k8s-cluster/main.tf

resource "aws_vpc" "k8s_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
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

resource "aws_subnet" "public_subnets" {
  count             = 2
  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.cluster_name}-public-subnet-${count.index}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route" "igw_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "control_plane_sg" {
  name        = "${var.cluster_name}-control-plane-sg"
  description = "Allow SSH, Kubernetes API, and internal VPC traffic"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubernetes API traffic"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Allow all traffic within the VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
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
  subnet_id                   = aws_subnet.public_subnets[0].id
  key_name                    = var.key_pair_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.control_plane_sg.id]

  user_data = file("${path.module}/user_data_control_plane.sh")
  iam_instance_profile = aws_iam_instance_profile.control_plane_profile.name

  tags = {
    Name = "${var.cluster_name}-control-plane"
  }
}

resource "aws_eip" "control_plane_eip" {
  instance = aws_instance.control_plane.id

  tags = {
    Name = "${var.cluster_name}-control-plane-eip"
  }
}

resource "aws_security_group" "worker_sg" {
  name        = "${var.cluster_name}-worker-sg"
  description = "Allow traffic for worker nodes"
  vpc_id      = aws_vpc.k8s_vpc.id

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
    cidr_blocks = [var.vpc_cidr]
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

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.worker_sg.id]
  }

  user_data = base64encode(file("${path.module}/user_data_worker.sh"))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-worker"
    }
  }
}

resource "aws_autoscaling_group" "worker_asg" {
  name                      = "${var.cluster_name}-worker-asg"
  desired_capacity          = var.desired_worker_nodes
  max_size                  = var.max_worker_nodes
  min_size                  = var.min_worker_nodes
  vpc_zone_identifier       = aws_subnet.public_subnets[*].id
  health_check_type         = "EC2"

  launch_template {
    id      = aws_launch_template.worker_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-worker"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}