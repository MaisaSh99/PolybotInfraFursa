#!/bin/bash
# scripts/refresh-k8s-join-token.sh

# Generate new kubeadm join command with sudo
JOIN_CMD=$(echo "sudo $(kubeadm token create --print-join-command)")

# Save it to a temporary file
echo "$JOIN_CMD" > /tmp/k8s_join.sh

# Install AWS CLI if missing
if ! command -v aws &> /dev/null; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
fi

# Update Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id K8S_JOIN_COMMAND \
  --secret-string file:///tmp/k8s_join.sh \
  --region us-east-2