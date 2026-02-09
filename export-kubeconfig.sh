#!/bin/bash
set -euo pipefail

# =============================================================================
# Exporta o kubeconfig do cluster para o host
# Automaticamente substitui o IP do node pelo VIP (kube-vip)
# =============================================================================

echo "=== Exportando kubeconfig ==="

# Cria o diretorio .kube se nao existir
mkdir -p ~/.kube

# Exporta o kubeconfig
vagrant ssh control-plane-1 -- -T sudo cat /etc/kubernetes/admin.conf > ~/.kube/config 2>/dev/null

# Ajusta permissoes
chmod 600 ~/.kube/config

# Obtem o IP atual do kubeconfig
CURRENT_IP=$(grep "server:" ~/.kube/config | awk -F'[:/]' '{print $4}')

# Calcula o VIP baseado no IP (x.x.x.100)
IP_PREFIX=$(echo "$CURRENT_IP" | cut -d'.' -f1-3)
VIP="${IP_PREFIX}.100"

# Verifica se o VIP esta respondendo
echo "[INFO] Verificando VIP ${VIP}..."
if ping -c 1 -W 2 "${VIP}" &>/dev/null; then
  echo "[OK] VIP ${VIP} esta ativo"
  
  # Substitui o IP pelo VIP no kubeconfig
  sed -i "s|https://${CURRENT_IP}:6443|https://${VIP}:6443|" ~/.kube/config
  echo "[OK] kubeconfig atualizado para usar VIP: ${VIP}"
else
  echo "[WARN] VIP ${VIP} nao esta respondendo, usando IP do node: ${CURRENT_IP}"
fi

echo ""
echo "[OK] kubeconfig exportado para ~/.kube/config"
echo "[INFO] API Server: $(grep "server:" ~/.kube/config | awk '{print $2}')"
echo ""
echo "[INFO] Testando conexao:"
kubectl get nodes -owide

