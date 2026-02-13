#!/bin/bash
set -euo pipefail

# =============================================================================
# Control Plane Setup com HAProxy para HA
# O HAProxy deve estar rodando antes de inicializar o cluster
# =============================================================================

HOSTNAME=$(hostname)
NODE_NUMBER="${NODE_NUMBER:-1}"
K8S_FULL_VERSION="v1.35.0"
POD_CIDR="192.168.0.0/16"
CALICO_VERSION="v3.29.0"

# Detecta o IP da interface principal
NODE_IP=$(hostname -I | awk '{print $1}')

echo "=== [INFO] Control Plane setup on ${HOSTNAME} (node ${NODE_NUMBER}) ==="
echo "=== [INFO] Detected IP: ${NODE_IP} ==="

########################################
# Descobrir IP do HAProxy
########################################
discover_haproxy_ip() {
  # Tenta descobrir o HAProxy via DNS/hosts ou varrer a rede
  local HAPROXY_IP=""
  
  # Metodo 1: Arquivo de configuracao (se disponivel)
  if [ -f /root/haproxy-ip.txt ]; then
    HAPROXY_IP=$(cat /root/haproxy-ip.txt)
  fi
  
  # Metodo 2: Tentar resolver via hostname
  if [ -z "$HAPROXY_IP" ]; then
    HAPROXY_IP=$(getent hosts haproxy 2>/dev/null | awk '{print $1}' || true)
  fi
  
  # Metodo 3: Varrer IPs comuns no mesmo range
  if [ -z "$HAPROXY_IP" ]; then
    local IP_PREFIX=$(echo "$NODE_IP" | cut -d'.' -f1-3)
    for i in $(seq 2 254); do
      local TEST_IP="${IP_PREFIX}.${i}"
      if [ "$TEST_IP" != "$NODE_IP" ]; then
        if curl -sk --connect-timeout 1 "http://${TEST_IP}:8404/stats" &>/dev/null; then
          HAPROXY_IP="$TEST_IP"
          break
        fi
      fi
    done
  fi
  
  echo "$HAPROXY_IP"
}

echo "=== [INFO] Discovering HAProxy IP ==="
HAPROXY_IP=$(discover_haproxy_ip)

if [ -z "$HAPROXY_IP" ]; then
  echo "=== [ERROR] Could not find HAProxy. Make sure haproxy VM is running ==="
  echo "=== [INFO] You can set HAPROXY_IP manually in environment ==="
  exit 1
fi

echo "=== [INFO] HAProxy IP: ${HAPROXY_IP} ==="

# Salva o IP do HAProxy para uso posterior
echo "${HAPROXY_IP}" > /root/haproxy-ip.txt

########################################
# Instalar kubectl (control plane)
########################################
echo "=== [INFO] Installing kubectl ==="
apt-get install -y -qq kubectl >/dev/null
apt-mark hold kubectl >/dev/null 2>&1

########################################
# Registrar no HAProxy
########################################
register_in_haproxy() {
  local NODE_NAME=$1
  local NODE_IP=$2
  local HAPROXY_IP=$3
  
  echo "=== [INFO] Registering ${NODE_NAME} (${NODE_IP}) in HAProxy (${HAPROXY_IP}) ==="
  
  # Tenta registrar via SSH usando a chave do vagrant
  # A chave insecure do vagrant geralmente está disponível durante o boot inicial
  local SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes"
  
  # Tenta com a chave insecure padrão do Vagrant
  local VAGRANT_KEY="/vagrant/.vagrant/machines/haproxy/libvirt/private_key"
  local INSECURE_KEY="/home/vagrant/.ssh/id_rsa"
  
  local REGISTERED=false
  
  # Método 1: Tenta SSH como root (se configurado)
  # shellcheck disable=SC2029
  if ssh "$SSH_OPTS" root@"${HAPROXY_IP}" "/usr/local/bin/register-control-plane.sh ${NODE_NAME} ${NODE_IP}" 2>/dev/null; then
    REGISTERED=true
  # Método 2: Tenta SSH como vagrant com sudo
  elif ssh "$SSH_OPTS" vagrant@"${HAPROXY_IP}" "sudo /usr/local/bin/register-control-plane.sh ${NODE_NAME} ${NODE_IP}" 2>/dev/null; then
    REGISTERED=true
  fi
  
  if [ "$REGISTERED" = "true" ]; then
    echo "=== [INFO] Successfully registered ${NODE_NAME} in HAProxy ==="
  else
    echo "=== [WARN] Could not auto-register. Adding backend directly... ==="
    # Não falha - o kubeadm init vai funcionar mesmo sem o registro
    # porque usamos o IP local como advertiseAddress
  fi
}

########################################
# Primary Control Plane (node 1)
########################################
if [ "$NODE_NUMBER" = "1" ]; then
  echo "=== [INFO] Initializing primary control plane ==="

  # Configuracao do kubeadm
  # IMPORTANTE: Usamos o IP do node como controlPlaneEndpoint inicialmente
  # Depois o Makefile vai registrar no HAProxy e atualizar o kubeconfig
  cat <<EOF >/root/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${NODE_IP}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
timeouts:
  controlPlaneComponentHealthCheck: 2m0s
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: ${K8S_FULL_VERSION}
controlPlaneEndpoint: "${NODE_IP}:6443"
networking:
  podSubnet: ${POD_CIDR}
apiServer:
  certSANs:
  - "${HAPROXY_IP}"
  - "${NODE_IP}"
  - "127.0.0.1"
  - "localhost"
  - "kubernetes"
  - "kubernetes.default"
EOF

  # kubeadm init (idempotente)
  if [ ! -f /etc/kubernetes/admin.conf ]; then
    echo "=== [INFO] Running kubeadm init ==="
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

  # Aguarda API server estar pronto localmente
  echo "=== [INFO] Waiting for API server to be ready ==="
  for i in {1..30}; do
    if kubectl get nodes &>/dev/null; then
      echo "=== [INFO] API server is responding ==="
      break
    fi
    echo "Waiting for API server... (${i}/30)"
    sleep 5
  done

  ########################################
  # Calico CNI
  ########################################
  echo "=== [INFO] Installing Calico CNI ==="

  # Instala o operador Tigera (Calico)
  kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" 2>/dev/null || true

  # Aguarda o operador estar pronto
  echo "=== [INFO] Waiting for Tigera operator ==="
  kubectl wait --for=condition=Available --timeout=120s deployment/tigera-operator -n tigera-operator 2>/dev/null || sleep 30

  # Aplica a configuracao do Calico
  cat <<CALICOEOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: ${POD_CIDR}
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
CALICOEOF

  echo "=== [INFO] Waiting for Calico to be ready ==="
  kubectl wait --for=condition=Available --timeout=300s tigerastatus/calico 2>/dev/null || true

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

  # Salva o IP do HAProxy e IP do node para os outros nodes
  echo "${HAPROXY_IP}" > /root/haproxy-ip.txt
  echo "${NODE_IP}" > /root/control-plane-ip.txt

  echo "=== [INFO] Primary Control Plane ready ==="
  echo "=== [INFO] Node IP: ${NODE_IP} ==="
  echo "=== [INFO] HAProxy LB: ${HAPROXY_IP}:6443 ==="
  kubectl get nodes

########################################
# Secondary Control Planes (nodes 2, 3)
########################################
else
  echo "=== [INFO] Joining as secondary control plane ==="
  
  echo "=== [WARN] Secondary control planes require manual join ==="
  echo "=== [INFO] Run: ./join-control-planes.sh ==="
fi

echo "=== [INFO] Control Plane setup completed on ${HOSTNAME} ==="
