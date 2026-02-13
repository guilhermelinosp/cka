#!/bin/bash
set -euo pipefail

# =============================================================================
# Addons Setup - Metrics Server, Longhorn, MetalLB e NGINX Ingress
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
# Longhorn (Distributed Storage)
########################################
echo ""
echo "[INFO] Instalando Longhorn..."

# Versao estavel do Longhorn
LONGHORN_VERSION="v1.7.2"

# Conta o numero de workers (nodes sem role control-plane)
WORKER_COUNT=$(kubectl get nodes --no-headers | grep -v control-plane | wc -l)
echo "[INFO] Workers detectados: ${WORKER_COUNT}"

# Calcula replicas dinamicamente baseado no numero de workers
# - REPLICAS_HA: todos os workers (max HA)
# - REPLICAS_DEFAULT: metade dos workers, minimo 2, maximo workers
# - REPLICAS_MIN: minimo para HA (2 ou 1 se so tiver 1 worker)
if [ "$WORKER_COUNT" -le 1 ]; then
  REPLICAS_HA=1
  REPLICAS_DEFAULT=1
  REPLICAS_MIN=1
elif [ "$WORKER_COUNT" -le 3 ]; then
  REPLICAS_HA=$WORKER_COUNT
  REPLICAS_DEFAULT=2
  REPLICAS_MIN=2
else
  REPLICAS_HA=$WORKER_COUNT
  REPLICAS_DEFAULT=$(( (WORKER_COUNT + 1) / 2 ))  # Arredonda para cima
  REPLICAS_MIN=2
fi

echo "[INFO] Configurando replicas: HA=${REPLICAS_HA}, Default=${REPLICAS_DEFAULT}, Min=${REPLICAS_MIN}"

# Instala o Longhorn via manifest oficial
kubectl apply -f "https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORN_VERSION}/deploy/longhorn.yaml"

echo "[INFO] Aguardando Longhorn pods (isso pode demorar alguns minutos)..."

# Aguarda o namespace ser criado
sleep 10

# Aguarda os pods principais do Longhorn
kubectl wait --namespace longhorn-system \
  --for=condition=ready pod \
  --selector=app=longhorn-manager \
  --timeout=300s || true

kubectl wait --namespace longhorn-system \
  --for=condition=ready pod \
  --selector=app=longhorn-driver-deployer \
  --timeout=180s || true

# Aplica configuracoes customizadas (StorageClasses adicionais e NodePort UI)
# A StorageClass "longhorn" padrao e criada automaticamente pelo Longhorn
echo "[INFO] Aplicando StorageClasses adicionais e NodePort para UI..."
sed -e "s/__REPLICAS_HA__/${REPLICAS_HA}/g" \
    -e "s/__REPLICAS_DEFAULT__/${REPLICAS_DEFAULT}/g" \
    -e "s/__REPLICAS_MIN__/${REPLICAS_MIN}/g" \
    "${MANIFESTS_DIR}/longhorn-config.yaml" | kubectl apply -f -

# Marca a StorageClass longhorn como default (se ainda nao estiver)
kubectl annotate storageclass longhorn storageclass.kubernetes.io/is-default-class=true --overwrite 2>/dev/null || true

echo "[OK] Longhorn instalado"
echo "[INFO] StorageClasses: longhorn (default), longhorn-ha(${REPLICAS_HA}), longhorn-min(${REPLICAS_MIN}), longhorn-single(1)"
echo "[INFO] UI do Longhorn disponivel em: http://<node-ip>:30080"

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
echo "[INFO] StorageClasses:"
kubectl get storageclass

echo ""
echo "[INFO] Longhorn pods:"
kubectl get pods -n longhorn-system | head -10

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
echo "[INFO] Acesse a UI do Longhorn em: http://<worker-ip>:30080"

