#!/bin/bash
set -euo pipefail

# =============================================================================
# Helper Script - Join workers ao cluster
# =============================================================================

echo "=== CKA Lab - Join Workers Helper ==="

# Obtém o IP do control-plane-1 (filtra warnings)
CP1_IP=$(vagrant ssh control-plane-1 -c "hostname -I | awk '{print \$1}'" 2>/dev/null | grep -v "warning:" | grep -v "^$" | tr -d '\r\n' | awk '{print $1}')

if [ -z "$CP1_IP" ]; then
  echo "❌ Erro: Não foi possível obter o IP do control-plane-1"
  echo "   Verifique se o control-plane-1 está rodando: vagrant status"
  exit 1
fi

echo "✅ Control Plane 1 IP: ${CP1_IP}"

# Obtém o comando de join (filtra warnings e pega só a linha do kubeadm)
echo "📋 Obtendo comando de join..."
JOIN_CMD=$(vagrant ssh control-plane-1 -c "sudo cat /root/join-worker.sh" 2>/dev/null | grep -v "warning:" | grep "kubeadm join" | tr -d '\r')

if [ -z "$JOIN_CMD" ]; then
  echo "❌ Erro: Não foi possível obter o comando de join"
  echo "   Verifique se o kubeadm init completou com sucesso"
  echo "   Tente: vagrant ssh control-plane-1 -c 'sudo cat /root/join-worker.sh'"
  exit 1
fi

echo "✅ Comando de join obtido"
echo ""

# Lista workers disponíveis
WORKERS=$(vagrant status 2>/dev/null | grep worker-node | grep running | awk '{print $1}')

if [ -z "$WORKERS" ]; then
  echo "⚠️  Nenhum worker node rodando"
  echo "   Inicie os workers: vagrant up worker-node-1 worker-node-2 ..."
  exit 0
fi

echo "🔄 Workers disponíveis:"
echo "$WORKERS"
echo ""

# Join cada worker
for WORKER in $WORKERS; do
  echo "➡️  Fazendo join do ${WORKER}..."
  
  # Verifica se já está no cluster
  ALREADY_JOINED=$(vagrant ssh "$WORKER" -c "test -f /etc/kubernetes/kubelet.conf && echo yes || echo no" 2>/dev/null | grep -v "warning:" | tr -d '\r\n')
  
  if [ "$ALREADY_JOINED" = "yes" ]; then
    echo "   ✅ ${WORKER} já está no cluster"
  else
    # Executa o join
    vagrant ssh "$WORKER" -c "sudo ${JOIN_CMD}" 2>&1 | grep -v "warning:" || true
    echo "   ✅ ${WORKER} adicionado ao cluster"
  fi
done

echo ""
echo "✅ Join completo!"
echo ""
echo "📋 Verificando nodes:"
vagrant ssh control-plane-1 -c "kubectl get nodes -owide" 2>&1 | grep -v "warning:"

