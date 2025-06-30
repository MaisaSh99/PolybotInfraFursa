# tf/outputs.tf

output "control_plane_asg_name" {
  description = "Auto Scaling Group name for control plane"
  value       = module.k8s_cluster.control_plane_asg_name
}

output "worker_asg_name" {
  description = "Auto Scaling Group name for worker nodes"
  value       = module.k8s_cluster.worker_asg_name
}

output "vpc_id" {
  description = "VPC ID where the cluster is deployed"
  value       = module.k8s_cluster.vpc_id
}