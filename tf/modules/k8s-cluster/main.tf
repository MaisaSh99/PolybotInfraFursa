#######################################
# 1. Networking                                                            #
#######################################

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

#######################################
# 2. IAM                                                                   #
#######################################

# ---- Control-plane role -------------------------------------------------
resource "aws_iam_role" "control_plane_role" {
  name = "${var.cluster_name}-control-plane-role"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Action    : "sts:AssumeRole",
      Effect    : "Allow",
      Principal : { Service : "ec2.amazonaws.com" }
    }]
  })
}

# Attach base policies (adjust these to least-privilege in future)
resource "aws_iam_role_policy_attachment" "control_plane_s3_access" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Add Secrets Manager access for the control plane
resource "aws_iam_role_policy_attachment" "control_plane_secrets_access" {
  role       = aws_iam_role.control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_instance_profile" "control_plane_profile" {
  name = "${var.cluster_name}-control-plane-profile"
  role = aws_iam_role.control_plane_role.name
}

# ---- Worker role (separate for PoLP) -----------------------------------
resource "aws_iam_role" "worker_role" {
  name = "${var.cluster_name}-worker-role"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Action    : "sts:AssumeRole",
      Effect    : "Allow",
      Principal : { Service : "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_ecr_readonly" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Add SSM access for workers to read join command
resource "aws_iam_role_policy_attachment" "worker_ssm_access" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.cluster_name}-worker-profile"
  role = aws_iam_role.worker_role.name
}

#######################################
# 3. Subnets & Routing                                                    #
#######################################

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.cluster_name}-public-${count.index}"
    "kubernetes.io/role/elb" = "1"   # handy for future LB
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
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

#######################################
# 4. Security Groups                                                      #
#######################################

resource "aws_security_group" "control_plane_sg" {
  name        = "${var.cluster_name}-control-plane-sg"
  description = "K8s control-plane access"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # tighten later
  }

  # etcd server client API
  ingress {
    description = "etcd server client API"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Kubelet API
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # kube-scheduler
  ingress {
    description = "kube-scheduler"
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # kube-controller-manager
  ingress {
    description = "kube-controller-manager"
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-control-plane-sg" }
}

resource "aws_security_group" "worker_sg" {
  name        = "${var.cluster_name}-worker-sg"
  description = "K8s workers"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubelet API
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # NodePort Services
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Pods / intra-cluster"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-worker-sg" }
}

#######################################
# 5. Elastic IP for Control Plane                                         #
#######################################

resource "aws_eip" "control_plane_eip" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-control-plane-eip"
  }
}

#######################################
# 6. CONTROL-PLANE ASG                                                   #
#######################################

resource "aws_launch_template" "control_plane_template" {
  name_prefix   = "${var.cluster_name}-control-plane-"
  image_id      = var.ami_id
  instance_type = var.instance_type_control_plane
  key_name      = var.key_pair_name

  iam_instance_profile {
    name = aws_iam_instance_profile.control_plane_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.control_plane_sg.id]
  }

  user_data = base64encode(templatefile("${path.module}/user_data_control_plane.sh", {
    eip_allocation_id = aws_eip.control_plane_eip.id
    region           = var.region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-control-plane"
      Type = "control-plane"
    }
  }
}

resource "aws_autoscaling_group" "control_plane_asg" {
  name                = "${var.cluster_name}-control-plane-asg"
  min_size            = var.min_control_plane_nodes
  desired_capacity    = var.desired_control_plane_nodes
  max_size            = var.max_control_plane_nodes
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.control_plane_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-control-plane"
    propagate_at_launch = true
  }

  tag {
    key                 = "Type"
    value               = "control-plane"
    propagate_at_launch = true
  }

  lifecycle { create_before_destroy = true }
}

#######################################
# 7. WORKER Launch Template + ASG                                         #
#######################################

resource "aws_launch_template" "worker_template" {
  name_prefix   = "${var.cluster_name}-worker-"
  image_id      = var.ami_id
  instance_type = var.instance_type_worker
  key_name      = var.key_pair_name

  iam_instance_profile { name = aws_iam_instance_profile.worker_profile.name }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.worker_sg.id]
  }

  user_data = base64encode(templatefile("${path.module}/user_data_worker.sh", {
    region = var.region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-worker"
      Type = "worker"
    }
  }
}

resource "aws_autoscaling_group" "worker_asg" {
  name                = "${var.cluster_name}-worker-asg"
  min_size            = var.min_worker_nodes
  desired_capacity    = var.desired_worker_nodes
  max_size            = var.max_worker_nodes
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  health_check_type   = "EC2"

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
    key                 = "Type"
    value               = "worker"
    propagate_at_launch = true
  }

  lifecycle { create_before_destroy = true }
}