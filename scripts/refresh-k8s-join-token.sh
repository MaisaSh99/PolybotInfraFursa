#!/bin/bash
# scripts/refresh-k8s-join-token.sh

set -e  # Exit on any error

echo "=== Refresh K8s Join Token Script ==="

# Check if required environment variables are set
if [[ -z "$AWS_REGION" ]]; then
    echo "ERROR: AWS_REGION environment variable is not set"
    exit 1
fi

if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
    echo "ERROR: AWS_ACCESS_KEY_ID environment variable is not set"
    exit 1
fi

if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
    echo "ERROR: AWS_SECRET_ACCESS_KEY environment variable is not set"
    exit 1
fi

echo "Using AWS region: $AWS_REGION"

# Configure AWS CLI with the region
aws configure set region $AWS_REGION
aws configure set default.region $AWS_REGION

# Test AWS connectivity
echo "=== Testing AWS connectivity ==="
aws sts get-caller-identity

# Generate new kubeadm join command with sudo
echo "=== Generating new join command ==="
JOIN_CMD=$(echo "sudo $(kubeadm token create --print-join-command)")

if [[ -z "$JOIN_CMD" ]]; then
    echo "ERROR: Failed to generate join command"
    exit 1
fi

echo "Generated join command: ${JOIN_CMD:0:50}..."

# Save it to a temporary file
echo "$JOIN_CMD" > /tmp/k8s_join.sh

# Verify the file was created
if [[ ! -f /tmp/k8s_join.sh ]]; then
    echo "ERROR: Failed to create join command file"
    exit 1
fi

echo "Join command saved to /tmp/k8s_join.sh"

# Install AWS CLI if missing
if ! command -v aws &> /dev/null; then
    echo "=== Installing AWS CLI ==="
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    # Re-configure after installation
    aws configure set region $AWS_REGION
    aws configure set default.region $AWS_REGION
fi

# Update Secrets Manager
echo "=== Updating Secrets Manager ==="
aws secretsmanager put-secret-value \
    --secret-id K8S_JOIN_COMMAND \
    --secret-string file:///tmp/k8s_join.sh \
    --region $AWS_REGION

echo "=== Secret updated successfully ==="

# Clean up
rm -f /tmp/k8s_join.sh

echo "=== Refresh completed successfully ==="