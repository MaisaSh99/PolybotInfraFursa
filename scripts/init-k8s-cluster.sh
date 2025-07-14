#!/bin/bash
# scripts/init-k8s-cluster.sh

set -e

# Only run if kubeadm hasn't already been initialized
if [ ! -f /etc/kubernetes/admin.conf ]; then
    echo "[INFO] Getting public IP for API server..."
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    echo "[INFO] Public IP: $PUBLIC_IP"

    echo "[INFO] Running kubeadm init with public IP..."
    sudo kubeadm init \
        --pod-network-cidr=192.168.0.0/16 \
        --apiserver-advertise-address=$PUBLIC_IP \
        --apiserver-cert-extra-sans=$PUBLIC_IP

    echo "[INFO] Setting up kubeconfig for ubuntu user..."
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Update kubeconfig to use public IP
    sed -i "s|server: https://.*:6443|server: https://$PUBLIC_IP:6443|g" $HOME/.kube/config

    echo "[INFO] Installing Calico CNI"
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/calico.yaml

    echo "[INFO] Waiting for nodes to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s

    echo "[INFO] Kubernetes cluster initialization complete!"
    kubectl get nodes
else
    echo "[INFO] Kubernetes already initialized. Ensuring kubeconfig is properly configured..."

    # Get public IP
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

    # Ensure user kubeconfig exists and uses public IP
    if [ ! -f $HOME/.kube/config ]; then
        mkdir -p $HOME/.kube
        sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
    fi

    # Update kubeconfig to use public IP
    sed -i "s|server: https://.*:6443|server: https://$PUBLIC_IP:6443|g" $HOME/.kube/config

    # Run the API server fix script if it exists
    if [ -f /home/ubuntu/fix-api-server.sh ]; then
        echo "[INFO] Running API server fix script..."
        /home/ubuntu/fix-api-server.sh
    fi

    echo "[INFO] Cluster already initialized and configured."
fi