#!/bin/bash
# scripts/refresh-k8s-join-token.sh - IMPROVED VERSION

set -e

echo "=== Improved Refresh K8s Join Token Script ==="

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

# Check if kubectl is working locally first
echo "=== Testing local kubectl access ==="
if ! kubectl get nodes --kubeconfig=/etc/kubernetes/admin.conf &> /dev/null; then
    echo "ERROR: kubectl not working locally. Cannot generate join token."
    exit 1
fi

# Generate a fresh join token that won't expire for 24 hours
echo "=== Generating new join token ==="
NEW_TOKEN=$(kubeadm token create --ttl 24h0m0s)

if [[ -z "$NEW_TOKEN" ]]; then
    echo "ERROR: Failed to generate new token"
    exit 1
fi

echo "Generated new token: $NEW_TOKEN"

# Get the discovery token CA cert hash
DISCOVERY_HASH="sha256:$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')"

echo "Discovery hash: $DISCOVERY_HASH"

# Create the join command with PRIVATE IP (for worker nodes)
PRIVATE_IP="10.0.0.233"
JOIN_CMD="sudo kubeadm join $PRIVATE_IP:6443 --token $NEW_TOKEN --discovery-token-ca-cert-hash $DISCOVERY_HASH"

echo "Generated join command: $JOIN_CMD"

# Save it to a temporary file
echo "$JOIN_CMD" > /tmp/k8s_join.sh

# Verify the file was created
if [[ ! -f /tmp/k8s_join.sh ]]; then
    echo "ERROR: Failed to create join command file"
    exit 1
fi

echo "Join command saved to /tmp/k8s_join.sh"

# Update Secrets Manager
echo "=== Updating Secrets Manager ==="
aws secretsmanager put-secret-value \
    --secret-id K8S_JOIN_COMMAND \
    --secret-string file:///tmp/k8s_join.sh \
    --region $AWS_REGION

echo "=== Secret updated successfully ==="

# Verify the update
echo "=== Verifying secret update ==="
STORED_COMMAND=$(aws secretsmanager get-secret-value --secret-id K8S_JOIN_COMMAND --region $AWS_REGION --query SecretString --output text)

if [[ "$STORED_COMMAND" == "$JOIN_CMD" ]]; then
    echo "✅ Secret verification successful"
else
    echo "❌ Secret verification failed"
    echo "Expected: $JOIN_CMD"
    echo "Got: $STORED_COMMAND"
    exit 1
fi

# Clean up
rm -f /tmp/k8s_join.sh

echo "=== Token refresh completed successfully ==="
echo "New token is valid for 24 hours"
echo "Worker nodes will now automatically join using: $JOIN_CMD"