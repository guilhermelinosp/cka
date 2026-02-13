#!/bin/bash
set -euo pipefail

# =============================================================================
# Common Setup - Executado em TODOS os nodes (Control Plane e Workers)
# =============================================================================

HOSTNAME=$(hostname)
K8S_VERSION="v1.35"
K8S_FULL_VERSION="v1.35.0"
PAUSE_IMAGE="registry.k8s.io/pause:3.10.1"
COREDNS_IMAGE="registry.k8s.io/coredns/coredns:v1.13.1"
ETCD_IMAGE="registry.k8s.io/etcd:3.5.21-0"

echo "=== [INFO] Common setup on ${HOSTNAME} ==="

########################################
# Locale (evita warnings de LC_ALL)
########################################
echo "=== [INFO] Configuring locale ==="

apt-get update -qq
apt-get install -y -qq locales >/dev/null
sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen
locale-gen en_US.UTF-8 >/dev/null
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

########################################
# Kernel Modules
########################################
echo "=== [INFO] Loading kernel modules ==="

cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

########################################
# Sysctl
########################################
echo "=== [INFO] Configuring sysctl ==="

cat <<EOF >/etc/sysctl.d/99-kubernetes.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system >/dev/null 2>&1

########################################
# Disable Swap
########################################
echo "=== [INFO] Disabling swap ==="

swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

########################################
# Packages
########################################
echo "=== [INFO] Installing packages ==="

apt-get update -qq
apt-get install -y -qq \
  ca-certificates \
  curl \
  gnupg \
  jq \
  apt-transport-https \
  open-iscsi \
  nfs-common \
  >/dev/null

########################################
# Longhorn Prerequisites (iSCSI)
########################################
echo "=== [INFO] Configuring iSCSI for Longhorn ==="

systemctl enable iscsid
systemctl start iscsid

########################################
# Containerd
########################################
echo "=== [INFO] Installing containerd ==="

apt-get install -y -qq containerd >/dev/null

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

########################################
# Kubernetes Repo
########################################
echo "=== [INFO] Configuring Kubernetes repo ==="

mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /
EOF

apt-get update -qq

########################################
# Kubelet & Kubeadm (todos os nodes)
########################################
echo "=== [INFO] Installing kubelet and kubeadm ==="

apt-get install -y -qq kubelet kubeadm cri-tools >/dev/null
apt-mark hold kubelet kubeadm >/dev/null

########################################
# Pre-pull de imagens (acelera provisionamento)
########################################
echo "=== [INFO] Pre-pulling Kubernetes images ==="

crictl pull "${PAUSE_IMAGE}" >/dev/null 2>&1 || true
crictl pull "${COREDNS_IMAGE}" >/dev/null 2>&1 || true
crictl pull "${ETCD_IMAGE}" >/dev/null 2>&1 || true
crictl pull "registry.k8s.io/kube-apiserver:${K8S_FULL_VERSION}" >/dev/null 2>&1 || true
crictl pull "registry.k8s.io/kube-controller-manager:${K8S_FULL_VERSION}" >/dev/null 2>&1 || true
crictl pull "registry.k8s.io/kube-scheduler:${K8S_FULL_VERSION}" >/dev/null 2>&1 || true
crictl pull "registry.k8s.io/kube-proxy:${K8S_FULL_VERSION}" >/dev/null 2>&1 || true

echo "=== [INFO] Common setup completed on ${HOSTNAME} ==="

