#!/bin/bash
set -euo pipefail

# =============================================================================
# Addons Setup - Metrics Server, HostPath Provisioner, MetalLB e NGINX Ingress
# Requer kubectl configurado no host (execute export-kubeconfig.sh primeiro)
# =============================================================================

echo "=== CKA Lab - Addons Setup ==="

# Diretorio do script e raiz do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
MANIFESTS_DIR="${PROJECT_ROOT}/manifests"

# Verifica se kubectl esta configurado
if ! kubectl cluster-info &>/dev/null; then
  echo "[ERROR] kubectl nao esta configurado. Execute primeiro:"
  echo "        ./export-kubeconfig.sh"
  exit 1
fi

########################################
# Metrics Server (essencial para CKA)
########################################
echo "[INFO] Instalando Metrics Server..."

kubectl apply -f "${MANIFESTS_DIR}/metrics-server.yaml"

echo "[INFO] Aguardando Metrics Server..."
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=k8s-app=metrics-server \
  --timeout=120s || true

echo "[OK] Metrics Server instalado (kubectl top nodes/pods)"

########################################
# HostPath Provisioner (Storage)
########################################
echo ""
echo "[INFO] Instalando HostPath Provisioner..."

kubectl apply -f "${MANIFESTS_DIR}/hostpath-provisioner.yaml"

echo "[INFO] Aguardando HostPath Provisioner..."
kubectl wait --namespace hostpath-system \
  --for=condition=ready pod \
  --selector=app=hostpath-provisioner \
  --timeout=120s || true

echo "[OK] HostPath Provisioner instalado (StorageClass padrao: hostpath)"

########################################
# MetalLB
########################################
echo ""
echo "[INFO] Instalando MetalLB..."

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

echo "[INFO] Aguardando MetalLB pods..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s || true

echo "[INFO] Configurando MetalLB IP Pool..."
kubectl apply -f "${MANIFESTS_DIR}/metallb-config.yaml"

echo "[OK] MetalLB instalado"

########################################
# NGINX Ingress Controller
########################################
echo ""
echo "[INFO] Instalando NGINX Ingress Controller..."

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/baremetal/deploy.yaml

echo "[INFO] Aguardando recursos serem criados..."
sleep 5

echo "[INFO] Removendo Deployment original..."
kubectl delete deployment ingress-nginx-controller -n ingress-nginx --ignore-not-found=true

echo "[INFO] Aplicando DaemonSet..."
kubectl apply -f "${MANIFESTS_DIR}/ingress-nginx-daemonset.yaml"

echo "[INFO] Configurando Service como LoadBalancer..."
kubectl apply -f "${MANIFESTS_DIR}/ingress-nginx-service.yaml"

echo "[INFO] Aguardando NGINX Ingress pods..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s || true

echo "[OK] NGINX Ingress Controller instalado como DaemonSet"

########################################
# Verificacao
########################################
echo ""
echo "=== Verificando instalacao ==="

echo ""
echo "[INFO] Metrics Server:"
kubectl get pods -n kube-system -l k8s-app=metrics-server

echo ""
echo "[INFO] StorageClass:"
kubectl get storageclass

echo ""
echo "[INFO] HostPath Provisioner:"
kubectl get pods -n hostpath-system

echo ""
echo "[INFO] MetalLB pods:"
kubectl get pods -n metallb-system

echo ""
echo "[INFO] NGINX Ingress pods:"
kubectl get pods -n ingress-nginx | head -5

echo ""
echo "[INFO] Services LoadBalancer:"
kubectl get svc -n ingress-nginx

echo ""
echo "[OK] Addons instalados com sucesso!"
echo ""
echo "[INFO] Teste o Metrics Server com: kubectl top nodes"

