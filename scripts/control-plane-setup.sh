#!/bin/bash
set -euo pipefail

# =============================================================================
# Control Plane Setup com kube-vip para HA
# VIP e calculado dinamicamente baseado no IP do node
# =============================================================================

HOSTNAME=$(hostname)
NODE_NUMBER="${NODE_NUMBER:-1}"
POD_CIDR="10.0.0.0/16"

# Detecta o IP da interface principal
NODE_IP=$(hostname -I | awk '{print $1}')

# Detecta a interface de rede principal
VIP_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)

# Calcula o VIP baseado no IP do node (usa .100 do mesmo range)
IP_PREFIX=$(echo "$NODE_IP" | cut -d'.' -f1-3)
VIP="${IP_PREFIX}.100"

echo "=== [INFO] Control Plane setup on ${HOSTNAME} (node ${NODE_NUMBER}) ==="
echo "=== [INFO] Detected IP: ${NODE_IP} ==="
echo "=== [INFO] VIP: ${VIP} ==="
echo "=== [INFO] Interface: ${VIP_INTERFACE} ==="

########################################
# Instalar kubectl (control plane)
########################################
echo "=== [INFO] Installing kubectl ==="
apt-get install -y -qq kubectl >/dev/null
apt-mark hold kubectl >/dev/null 2>&1

########################################
# kube-vip manifest (static pod)
########################################
generate_kube_vip_manifest() {
  local VIP_ADDR=$1
  local VIP_IFACE=$2
  
  echo "=== [INFO] Generating kube-vip manifest ==="
  
  mkdir -p /etc/kubernetes/manifests
  
  cat <<EOF >/etc/kubernetes/manifests/kube-vip.yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-vip
  namespace: kube-system
spec:
  containers:
  - name: kube-vip
    image: ghcr.io/kube-vip/kube-vip:v0.8.7
    imagePullPolicy: IfNotPresent
    args:
    - manager
    env:
    - name: vip_arp
      value: "true"
    - name: port
      value: "6443"
    - name: vip_interface
      value: "${VIP_IFACE}"
    - name: vip_cidr
      value: "32"
    - name: dns_mode
      value: "first"
    - name: cp_enable
      value: "true"
    - name: cp_namespace
      value: kube-system
    - name: svc_enable
      value: "false"
    - name: vip_leaderelection
      value: "true"
    - name: vip_leasename
      value: plndr-cp-lock
    - name: vip_leaseduration
      value: "5"
    - name: vip_renewdeadline
      value: "3"
    - name: vip_retryperiod
      value: "1"
    - name: address
      value: "${VIP_ADDR}"
    - name: prometheus_server
      value: :2112
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
  hostAliases:
  - hostnames:
    - kubernetes
    ip: 127.0.0.1
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/admin.conf
      type: FileOrCreate
    name: kubeconfig
EOF
}

########################################
# Primary Control Plane (node 1)
########################################
if [ "$NODE_NUMBER" = "1" ]; then
  echo "=== [INFO] Initializing primary control plane ==="

  # IMPORTANTE: Primeiro faz kubeadm init com o IP do node
  # O VIP sera configurado depois que o admin.conf existir
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
apiServer:
  certSANs:
  - "${VIP}"
  - "${NODE_IP}"
  - "127.0.0.1"
  - "localhost"
  - "kubernetes"
  - "kubernetes.default"
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "none"
EOF

  # kubeadm init (idempotente)
  if [ ! -f /etc/kubernetes/admin.conf ]; then
    # Primeiro, inicializa SEM o kube-vip (usando IP do node)
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

  # Agora que o admin.conf existe, gera o manifest do kube-vip
  generate_kube_vip_manifest "${VIP}" "${VIP_INTERFACE}"

  # Aguarda o kube-vip assumir o VIP
  echo "=== [INFO] Waiting for kube-vip to claim VIP ${VIP} ==="
  for i in {1..30}; do
    if ping -c 1 -W 1 "${VIP}" &>/dev/null; then
      echo "=== [INFO] VIP ${VIP} is now active ==="
      break
    fi
    echo "Waiting for VIP... (${i}/30)"
    sleep 2
  done

  # Aguarda API server responder no VIP
  echo "=== [INFO] Waiting for API server on VIP ==="
  until curl -sk "https://${VIP}:6443/healthz" &>/dev/null; do
    sleep 5
  done
  echo "=== [INFO] API server is responding on VIP ==="

  ########################################
  # Cilium CLI
  ########################################
  echo "=== [INFO] Installing Cilium CLI ==="

  if ! command -v cilium &>/dev/null; then
    curl -sL --fail https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz \
      | tar xz -C /usr/local/bin
  fi

  ########################################
  # Cilium Install - usa o IP do node
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

  ########################################
  # Remove kube-proxy (Cilium substitui)
  ########################################
  echo "=== [INFO] Removing kube-proxy (replaced by Cilium) ==="
  kubectl delete daemonset kube-proxy -n kube-system --ignore-not-found=true
  kubectl delete configmap kube-proxy -n kube-system --ignore-not-found=true

  echo "=== [INFO] Waiting for Cilium to be ready ==="
  cilium status --wait || true

  ########################################
  # Generate Join Commands
  ########################################
  echo "=== [INFO] Generating join commands ==="

  # Worker join command
  kubeadm token create --print-join-command > /root/join-worker.sh
  chmod +x /root/join-worker.sh
  
  # Copia para vagrant tambem
  cp /root/join-worker.sh /home/vagrant/
  chown vagrant:vagrant /home/vagrant/join-worker.sh

  # Control plane join command (com certificates)
  CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -n1)
  kubeadm token create --print-join-command \
    --certificate-key "$CERT_KEY" \
    > /root/join-control-plane.sh
  chmod +x /root/join-control-plane.sh

  # Salva o VIP e IP para os outros nodes
  echo "${VIP}" > /root/control-plane-vip.txt
  echo "${NODE_IP}" > /root/control-plane-ip.txt

  echo "=== [INFO] Primary Control Plane ready ==="
  echo "=== [INFO] Node IP: ${NODE_IP} ==="
  echo "=== [INFO] VIP: ${VIP} (kube-vip) ==="
  kubectl get nodes

########################################
# Secondary Control Planes (nodes 2, 3)
########################################
else
  echo "=== [INFO] Joining as secondary control plane ==="
  
  # Gera manifest do kube-vip para este node tambem
  generate_kube_vip_manifest "${VIP}" "${VIP_INTERFACE}"
  
  echo "=== [WARN] Secondary control planes require manual join ==="
  echo "=== [INFO] Run: ./join-control-planes.sh ==="
fi

echo "=== [INFO] Control Plane setup completed on ${HOSTNAME} ==="
