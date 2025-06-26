#!/bin/bash
# scripts/init-k8s-cluster.sh

set -e

# Only run if kubeadm hasn't already been initialized
if [ ! -f /etc/kubernetes/admin.conf ]; then
    echo "[INFO] Running kubeadm init..."
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    echo "[INFO] Installing Calico CNI"
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/calico.yaml
else
    echo "[INFO] Kubernetes already initialized. Skipping."
fi