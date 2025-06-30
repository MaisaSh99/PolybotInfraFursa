# tf/modules/k8s-cluster/outputs.tf

# Since we're using ASG, we can't have a static EIP
# Instead, we'll output the ASG name so external scripts can query for instances
output "control_plane_asg_name" {
  description = "Name of the Auto Scaling Group for control plane"
  value       = aws_autoscaling_group.control_plane_asg.name
}

output "worker_asg_name" {
  description = "Name of the Auto Scaling Group for workers"
  value       = aws_autoscaling_group.worker_asg.name
}

# You can also output the VPC and security group info for reference
output "vpc_id" {
  description = "ID of the VPC created for the cluster"
  value       = aws_vpc.k8s_vpc.id
}

output "control_plane_security_group_id" {
  description = "Security group ID for control plane"
  value       = aws_security_group.control_plane_sg.id
}