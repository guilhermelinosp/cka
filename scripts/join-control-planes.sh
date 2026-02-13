#!/bin/bash
set -euo pipefail

# =============================================================================
# Helper Script - Join control planes adicionais ao cluster
# Com suporte a HAProxy para HA
# =============================================================================

echo "=== CKA Lab - Join Control Planes Helper ==="

# Obtem o IP do HAProxy do control-plane-1
echo "[INFO] Obtendo IP do HAProxy..."
HAPROXY_IP=$(vagrant ssh control-plane-1 -- -T "sudo cat /root/haproxy-ip.txt" 2>/dev/null | tr -d '\r\n')

if [ -z "$HAPROXY_IP" ]; then
  echo "[WARN] IP do HAProxy nao encontrado, tentando descobrir..."
  HAPROXY_IP=$(vagrant ssh haproxy -- -T "hostname -I | awk '{print \$1}'" 2>/dev/null | tr -d '\r\n')
fi

if [ -z "$HAPROXY_IP" ]; then
  echo "[ERROR] Nao foi possivel obter o IP do HAProxy"
  exit 1
fi

echo "[OK] HAProxy IP: ${HAPROXY_IP}"

# Obtem o comando de join para control-plane
echo "[INFO] Obtendo comando de join para control-plane..."
JOIN_CMD=$(vagrant ssh control-plane-1 -- -T "sudo cat /root/join-control-plane.sh" 2>/dev/null | grep "kubeadm join" | tr -d '\r')

if [ -z "$JOIN_CMD" ]; then
  echo "[ERROR] Nao foi possivel obter o comando de join"
  echo "        Verifique se o kubeadm init completou com sucesso"
  exit 1
fi

echo "[OK] Comando de join obtido"
echo ""

# Lista control planes disponiveis (exceto o 1)
CONTROL_PLANES=$(vagrant status 2>/dev/null | grep control-plane | grep running | awk '{print $1}' | grep -v "control-plane-1")

if [ -z "$CONTROL_PLANES" ]; then
  echo "[WARN] Nenhum control plane adicional rodando"
  echo "       Inicie os control planes: vagrant up control-plane-2 control-plane-3"
  exit 0
fi
echo "[INFO] Control Planes disponiveis para join:"

echo "$CONTROL_PLANES"
echo ""

# Join cada control plane
for CP in $CONTROL_PLANES; do
  echo "[INFO] Fazendo join do ${CP}..."
  
  # Verifica se ja esta no cluster
  ALREADY_JOINED=$(vagrant ssh "$CP" -- -T "test -f /etc/kubernetes/admin.conf && echo yes || echo no" 2>/dev/null | tr -d '\r\n')
  
  if [ "$ALREADY_JOINED" = "yes" ]; then
    echo "       [OK] ${CP} ja esta no cluster"
  else
    # Obtem o IP do node
    NODE_IP=$(vagrant ssh "$CP" -- -T "hostname -I | awk '{print \$1}'" 2>/dev/null | tr -d '\r\n')
    
    # Registra este control plane no HAProxy
    echo "       [INFO] Registrando ${CP} no HAProxy..."
    vagrant ssh haproxy -- -T "sudo /usr/local/bin/register-control-plane.sh ${CP} ${NODE_IP}" 2>/dev/null || \
      echo "       [WARN] Nao foi possivel registrar automaticamente. Registre manualmente."
    
    echo "       [INFO] Executando join (isso pode demorar alguns minutos)..."
    vagrant ssh "$CP" -- -T "sudo ${JOIN_CMD}" 2>&1 || true
    
    # Configura kubectl para o usuario vagrant
    vagrant ssh "$CP" -- -T "sudo mkdir -p /home/vagrant/.kube && sudo cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config && sudo chown -R vagrant:vagrant /home/vagrant/.kube" 2>&1 || true
    
    echo "       [OK] ${CP} adicionado ao cluster"
  fi
done

echo ""
echo "[OK] Join completo!"
echo ""
echo "[INFO] HAProxy Load Balancer: ${HAPROXY_IP}:6443"
echo "[INFO] HAProxy Stats: http://${HAPROXY_IP}:8404/stats (admin:admin)"
echo ""
echo "[INFO] Verificando nodes:"
kubectl get nodes -owide 2>/dev/null || vagrant ssh control-plane-1 -- -T "kubectl get nodes -owide"
