#!/bin/bash
set -euo pipefail

# =============================================================================
# Exporta o kubeconfig do cluster para o host
# Usa o IP do control-plane-1 diretamente (HAProxy será configurado pelo Makefile)
# =============================================================================

echo "=== Exportando kubeconfig ==="

# Cria o diretorio .kube se nao existir
mkdir -p ~/.kube

# Exporta o kubeconfig
vagrant ssh control-plane-1 -- -T sudo cat /etc/kubernetes/admin.conf > ~/.kube/config 2>/dev/null

# Ajusta permissoes
chmod 600 ~/.kube/config

echo ""
echo "[OK] kubeconfig exportado para ~/.kube/config"
echo "[INFO] API Server: $(grep "server:" ~/.kube/config | awk '{print $2}')"
echo ""
echo "[INFO] Testando conexao:"
kubectl get nodes -owide || echo "[WARN] Cluster ainda inicializando..."

