#!/bin/bash
set -euo pipefail

# =============================================================================
# Helper Script - Join control planes adicionais ao cluster
# Com suporte a kube-vip para HA (VIP dinamico)
# =============================================================================

echo "=== CKA Lab - Join Control Planes Helper ==="

# Obtem o VIP do control-plane-1
echo "[INFO] Obtendo VIP do cluster..."
VIP=$(vagrant ssh control-plane-1 -- -T "sudo cat /root/control-plane-vip.txt" 2>/dev/null | tr -d '\r\n')

if [ -z "$VIP" ]; then
  echo "[WARN] VIP nao encontrado, calculando baseado no IP..."
  CP1_IP=$(vagrant ssh control-plane-1 -- -T "hostname -I | awk '{print \$1}'" 2>/dev/null | tr -d '\r\n')
  IP_PREFIX=$(echo "$CP1_IP" | cut -d'.' -f1-3)
  VIP="${IP_PREFIX}.100"
fi

echo "[OK] VIP: ${VIP}"

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
    # Detecta a interface de rede e atualiza o manifest do kube-vip
    echo "       [INFO] Atualizando manifest do kube-vip..."
    IFACE=$(vagrant ssh "$CP" -- -T "ip route | grep default | awk '{print \$5}' | head -1" 2>/dev/null | tr -d '\r\n')
    
    vagrant ssh "$CP" -- -T "sudo sed -i 's/value: \"eth0\"/value: \"${IFACE}\"/' /etc/kubernetes/manifests/kube-vip.yaml 2>/dev/null || true" || true
    
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
echo "[INFO] VIP do API Server: ${VIP}:6443"
echo ""
echo "[INFO] Verificando nodes:"
kubectl get nodes -owide 2>/dev/null || vagrant ssh control-plane-1 -- -T "kubectl get nodes -owide"
