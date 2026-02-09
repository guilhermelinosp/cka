#!/bin/bash
set -euo pipefail

# =============================================================================
# Helper Script - Join workers ao cluster
# =============================================================================

echo "=== CKA Lab - Join Workers Helper ==="

# Obtem o comando de join do control-plane-1
echo "[INFO] Obtendo comando de join..."
JOIN_CMD=$(vagrant ssh control-plane-1 -- -T "sudo cat /root/join-worker.sh" 2>/dev/null | grep "kubeadm join" | tr -d '\r')

if [ -z "$JOIN_CMD" ]; then
  echo "[ERROR] Nao foi possivel obter o comando de join"
  echo "        Verifique se o kubeadm init completou com sucesso"
  exit 1
fi

echo "[OK] Comando de join obtido"
echo ""

# Lista workers disponiveis
WORKERS=$(vagrant status 2>/dev/null | grep worker-node | grep running | awk '{print $1}')

if [ -z "$WORKERS" ]; then
  echo "[WARN] Nenhum worker node rodando"
  echo "       Inicie os workers: vagrant up worker-node-1 worker-node-2 ..."
  exit 0
fi

echo "[INFO] Workers disponiveis:"
echo "$WORKERS"
echo ""

# Join cada worker
for WORKER in $WORKERS; do
  echo "[INFO] Fazendo join do ${WORKER}..."
  
  # Verifica se ja esta no cluster
  ALREADY_JOINED=$(vagrant ssh "$WORKER" -- -T "test -f /etc/kubernetes/kubelet.conf && echo yes || echo no" 2>/dev/null | tr -d '\r\n')
  
  if [ "$ALREADY_JOINED" = "yes" ]; then
    echo "       [OK] ${WORKER} ja esta no cluster"
  else
    vagrant ssh "$WORKER" -- -T "sudo ${JOIN_CMD}" 2>&1 || true
    echo "       [OK] ${WORKER} adicionado ao cluster"
  fi
done

echo ""
echo "[OK] Join completo!"
echo ""
echo "[INFO] Verificando nodes:"
kubectl get nodes -owide 2>/dev/null || vagrant ssh control-plane-1 -- -T "kubectl get nodes -owide"

