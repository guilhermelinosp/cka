#!/bin/bash
set -euo pipefail

# =============================================================================
# Control Plane Setup
# Executa kubeadm init no node 1, e join nos demais (HA)
# =============================================================================

HOSTNAME=$(hostname)
NODE_NUMBER="${NODE_NUMBER:-1}"
POD_CIDR="10.0.0.0/16"

# Detecta o IP da interface principal (não localhost)
NODE_IP=$(hostname -I | awk '{print $1}')

echo "=== [INFO] Control Plane setup on ${HOSTNAME} (node ${NODE_NUMBER}) ==="
echo "=== [INFO] Detected IP: ${NODE_IP} ==="

########################################
# Instalar kubectl (control plane)
########################################
echo "=== [INFO] Installing kubectl ==="
apt-get install -y -qq kubectl >/dev/null
apt-mark hold kubectl >/dev/null 2>&1

########################################
# Primary Control Plane (node 1)
########################################
if [ "$NODE_NUMBER" = "1" ]; then
  echo "=== [INFO] Initializing primary control plane ==="

  # Kubeadm config
  cat <<EOF >/root/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${NODE_IP}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.35.0
controlPlaneEndpoint: "${NODE_IP}:6443"
networking:
  podSubnet: ${POD_CIDR}
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "none"
EOF

  # kubeadm init (idempotente)
  if [ ! -f /etc/kubernetes/admin.conf ]; then
    kubeadm init --config /root/kubeadm-config.yaml --upload-certs 2>&1 | tee /root/kubeadm-init.log
  fi

  export KUBECONFIG=/etc/kubernetes/admin.conf

  # Kubectl config para root
  mkdir -p /root/.kube
  cp -f /etc/kubernetes/admin.conf /root/.kube/config

  # Kubectl config para vagrant
  mkdir -p /home/vagrant/.kube
  cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
  chown -R vagrant:vagrant /home/vagrant/.kube

  # Aguarda API server
  echo "=== [INFO] Waiting for API server ==="
  until kubectl get nodes &>/dev/null; do
    sleep 5
  done

  ########################################
  # Cilium CLI
  ########################################
  echo "=== [INFO] Installing Cilium CLI ==="

  if ! command -v cilium &>/dev/null; then
    curl -sL --fail https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz \
      | tar xz -C /usr/local/bin
  fi

  ########################################
  # Cilium Install
  ########################################
  echo "=== [INFO] Installing Cilium CNI ==="

  if ! kubectl get ns cilium-system &>/dev/null 2>&1; then
    cilium install \
      --set kubeProxyReplacement=true \
      --set k8sServiceHost="${NODE_IP}" \
      --set k8sServicePort=6443 \
      --set ipam.mode=cluster-pool \
      --set ipam.operator.clusterPoolIPv4PodCIDRList="{${POD_CIDR}}" \
      --set ipam.operator.clusterPoolIPv4MaskSize=24 || true
  fi

  echo "=== [INFO] Waiting for Cilium to be ready ==="
  cilium status --wait || true

  ########################################
  # Generate Join Commands
  ########################################
  echo "=== [INFO] Generating join commands ==="

  # Worker join command
  kubeadm token create --print-join-command > /root/join-worker.sh
  chmod +x /root/join-worker.sh
  
  # Copia para vagrant também
  cp /root/join-worker.sh /home/vagrant/
  chown vagrant:vagrant /home/vagrant/join-worker.sh

  # Control plane join command (com certificates)
  CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -n1)
  kubeadm token create --print-join-command \
    --certificate-key "$CERT_KEY" \
    > /root/join-control-plane.sh
  chmod +x /root/join-control-plane.sh

  # Salva o IP do control-plane-1 para os outros nodes
  echo "${NODE_IP}" > /root/control-plane-ip.txt

  echo "=== [INFO] Primary Control Plane ready ==="
  echo "=== [INFO] Control Plane IP: ${NODE_IP} ==="
  kubectl get nodes

########################################
# Secondary Control Planes (nodes 2, 3)
########################################
else
  echo "=== [INFO] Joining as secondary control plane ==="
  echo "=== [WARN] Secondary control planes require manual join in DHCP environment ==="
  echo "=== [INFO] Run: scp root@<control-plane-1-ip>:/root/join-control-plane.sh /root/ && bash /root/join-control-plane.sh ==="
fi

echo "=== [INFO] Control Plane setup completed on ${HOSTNAME} ==="
