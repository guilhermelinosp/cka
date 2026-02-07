#!/bin/bash
set -euo pipefail

# =============================================================================
# Helper Script - Join control planes adicionais ao cluster
# Execute este script no host (não na VM)
# =============================================================================

echo "=== CKA Lab - Join Control Planes Helper ==="

# Obtém o IP do control-plane-1 (filtra warnings)
CP1_IP=$(vagrant ssh control-plane-1 -c "hostname -I | awk '{print \$1}'" 2>/dev/null | grep -v "warning:" | grep -v "^$" | tr -d '\r\n' | awk '{print $1}')

if [ -z "$CP1_IP" ]; then
  echo "❌ Erro: Não foi possível obter o IP do control-plane-1"
  echo "   Verifique se o control-plane-1 está rodando: vagrant status"
  exit 1
fi

echo "✅ Control Plane 1 IP: ${CP1_IP}"

# Obtém o comando de join para control-plane (filtra warnings e pega só a linha do kubeadm)
echo "📋 Obtendo comando de join para control-plane..."
JOIN_CMD=$(vagrant ssh control-plane-1 -c "sudo cat /root/join-control-plane.sh" 2>/dev/null | grep -v "warning:" | grep "kubeadm join" | tr -d '\r')

if [ -z "$JOIN_CMD" ]; then
  echo "❌ Erro: Não foi possível obter o comando de join"
  echo "   Verifique se o kubeadm init completou com sucesso"
  echo "   Tente: vagrant ssh control-plane-1 -c 'sudo cat /root/join-control-plane.sh'"
  exit 1
fi

echo "✅ Comando de join obtido"
echo ""

# Lista control planes disponíveis (exceto o 1)
CONTROL_PLANES=$(vagrant status 2>/dev/null | grep control-plane | grep running | awk '{print $1}' | grep -v "control-plane-1")

if [ -z "$CONTROL_PLANES" ]; then
  echo "⚠️  Nenhum control plane adicional rodando"
  echo "   Inicie os control planes: vagrant up control-plane-2 control-plane-3"
  exit 0
fi

echo "🔄 Control Planes disponíveis para join:"
echo "$CONTROL_PLANES"
echo ""

# Join cada control plane
for CP in $CONTROL_PLANES; do
  echo "➡️  Fazendo join do ${CP}..."
  
  # Verifica se já está no cluster
  ALREADY_JOINED=$(vagrant ssh "$CP" -c "test -f /etc/kubernetes/admin.conf && echo yes || echo no" 2>/dev/null | grep -v "warning:" | tr -d '\r\n')
  
  if [ "$ALREADY_JOINED" = "yes" ]; then
    echo "   ✅ ${CP} já está no cluster"
  else
    # Executa o join
    echo "   🔧 Executando join (isso pode demorar alguns minutos)..."
    vagrant ssh "$CP" -c "sudo ${JOIN_CMD}" 2>&1 | grep -v "warning:" || true
    
    # Configura kubectl para o usuário vagrant
    vagrant ssh "$CP" -c "sudo mkdir -p /home/vagrant/.kube && sudo cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config && sudo chown -R vagrant:vagrant /home/vagrant/.kube" 2>&1 | grep -v "warning:" || true
    
    echo "   ✅ ${CP} adicionado ao cluster"
  fi
done

echo ""
echo "✅ Join completo!"
echo ""
echo "📋 Verificando nodes:"
vagrant ssh control-plane-1 -c "kubectl get nodes -owide" 2>&1 | grep -v "warning:"

