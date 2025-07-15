#!/bin/bash
# tf/modules/k8s-cluster/user_data_worker.sh - FIXED VERSION

# These instructions are for Kubernetes v1.32
KUBERNETES_VERSION=v1.32
sudo apt-get update
sudo apt-get install -y jq unzip ebtables ethtool

# Install awscli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Enable IPv4 forwarding
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# Install cri-o and Kubernetes components
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/ /" | sudo tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get update
sudo apt-get install -y software-properties-common apt-transport-https ca-certificates curl gpg
sudo apt-get install -y cri-o kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Start CRI-O and kubelet
sudo systemctl start crio
sudo systemctl enable crio
sudo systemctl enable kubelet

# Disable swap
swapoff -a
(crontab -l ; echo "@reboot /sbin/swapoff -a") | crontab -

# === FIXED: Auto-join the worker node to the Kubernetes cluster ===
echo "=== Auto-joining worker node to Kubernetes cluster ==="

# Wait for AWS CLI to be ready
sleep 30

# Retry mechanism for joining the cluster
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES to join the cluster..."

    # Fetch the join command from AWS Secrets Manager
    JOIN_COMMAND=$(aws secretsmanager get-secret-value \
        --region us-east-2 \
        --secret-id K8S_JOIN_COMMAND \
        --query SecretString \
        --output text 2>/dev/null)

    if [ -n "$JOIN_COMMAND" ] && [ "$JOIN_COMMAND" != "null" ]; then
        echo "Retrieved join command successfully"
        echo "Join command: ${JOIN_COMMAND:0:50}..."

        # Execute the join command
        if eval "$JOIN_COMMAND"; then
            echo "✅ Successfully joined the Kubernetes cluster!"
            break
        else
            echo "❌ Join command failed, retrying in 30 seconds..."
        fi
    else
        echo "❌ Failed to retrieve join command from Secrets Manager, retrying in 30 seconds..."
    fi

    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 30
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Failed to join cluster after $MAX_RETRIES attempts"
    echo "Logging error details..."
    echo "AWS Region: us-east-2"
    echo "Secret ID: K8S_JOIN_COMMAND"

    # Try to get AWS identity for debugging
    aws sts get-caller-identity || echo "AWS CLI not working"

    # Check if we can reach the control plane
    ping -c 3 10.0.0.233 || echo "Cannot reach control plane"

    exit 1
else
    echo "✅ Worker node successfully joined the cluster on attempt $((RETRY_COUNT + 1))"
fi