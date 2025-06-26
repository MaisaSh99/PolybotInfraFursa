# ---- Cluster location -------------------------------------------------------
region              = "us-east-2"
availability_zones  = ["us-east-2a", "us-east-2b"]

# ---- Access -----------------------------------------------------------------
key_pair_name       = "m-polybot-key"

# ---- Naming -----------------------------------------------------------------
cluster_name        = "polybot-k8s"

# ---- Instance sizes ---------------------------------------------------------
instance_type_control_plane = "t2.medium"
instance_type_worker        = "t2.small"

# ---- Worker scaling ---------------------------------------------------------
min_worker_nodes     = 1
max_worker_nodes     = 3
desired_worker_nodes = 2

# ---- VPC --------------------------------------------------------------------
use_existing_vpc  = true
existing_vpc_name = "m-polybot-vpc"

# ---- AMI --------------------------------------------------------------------
ami_id = "ami-0d1b5a8c13042c939"   # ✅ new line
