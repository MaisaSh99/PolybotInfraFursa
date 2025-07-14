#!/bin/bash
# tf/modules/k8s-cluster/user_data_control_plane.sh
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

# Create a post-initialization script that will run after kubeadm init
cat > /home/ubuntu/fix-api-server.sh << 'EOF'
#!/bin/bash
# This script fixes the API server configuration to use the public IP

set -e
echo "=== Fixing API Server Configuration ==="

# Get the public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Public IP: $PUBLIC_IP"

# Wait for API server manifest to exist
while [ ! -f /etc/kubernetes/manifests/kube-apiserver.yaml ]; do
    echo "Waiting for API server manifest..."
    sleep 5
done

# Backup current API server configuration
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml.backup

# Update API server to advertise public IP
if ! sudo grep -q "advertise-address=$PUBLIC_IP" /etc/kubernetes/manifests/kube-apiserver.yaml; then
    echo "Adding advertise-address to API server..."
    sudo sed -i "/--advertise-address=/d" /etc/kubernetes/manifests/kube-apiserver.yaml
    sudo sed -i "/- kube-apiserver/a\\    - --advertise-address=$PUBLIC_IP" /etc/kubernetes/manifests/kube-apiserver.yaml

    echo "Waiting for API server to restart..."
    sleep 30

    # Wait for API server to be ready
    while ! kubectl get nodes --kubeconfig=/etc/kubernetes/admin.conf &> /dev/null; do
        echo "Waiting for API server to be ready..."
        sleep 10
    done
fi

# Setup user kubeconfig with public IP
mkdir -p /home/ubuntu/.kube
sudo cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Update kubeconfig to use public IP
sed -i "s|server: https://.*:6443|server: https://$PUBLIC_IP:6443|g" /home/ubuntu/.kube/config

echo "✅ API server configuration complete!"
echo "API server accessible at: https://$PUBLIC_IP:6443"
EOF

chmod +x /home/ubuntu/fix-api-server.sh