#!/bin/bash
set -euo pipefail

# =============================================================================
# Addons Setup - MetalLB e NGINX Ingress Controller
# Requer kubectl configurado no host (execute export-kubeconfig.sh primeiro)
# =============================================================================

echo "=== CKA Lab - Addons Setup ==="

# Diretorio do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verifica se kubectl esta configurado
if ! kubectl cluster-info &>/dev/null; then
  echo "[ERROR] kubectl nao esta configurado. Execute primeiro:"
  echo "        ./export-kubeconfig.sh"
  exit 1
fi

########################################
# MetalLB
########################################
echo "[INFO] Instalando MetalLB..."

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

echo "[INFO] Aguardando MetalLB pods..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s || true

echo "[INFO] Configurando MetalLB IP Pool..."
kubectl apply -f "${SCRIPT_DIR}/manifests/metallb-config.yaml"

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
kubectl apply -f "${SCRIPT_DIR}/manifests/ingress-nginx-daemonset.yaml"

echo "[INFO] Configurando Service como LoadBalancer..."
kubectl apply -f "${SCRIPT_DIR}/manifests/ingress-nginx-service.yaml"

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
echo "[INFO] MetalLB pods:"
kubectl get pods -n metallb-system -owide

echo ""
echo "[INFO] NGINX Ingress pods:"
kubectl get pods -n ingress-nginx -owide

echo ""
echo "[INFO] Services:"
kubectl get svc -n ingress-nginx

echo ""
echo "[OK] Addons instalados com sucesso!"

