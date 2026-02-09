#!/bin/bash
set -euo pipefail

# =============================================================================
# Worker Node Setup
# Aguarda o control-plane-1 e faz join no cluster
# =============================================================================

HOSTNAME=$(hostname)

echo "=== [INFO] Worker setup on ${HOSTNAME} ==="
echo "=== [WARN] Em ambiente DHCP, o join deve ser feito manualmente ==="
echo "=== [INFO] Passos para join manual: ==="
echo "  1. Descubra o IP do control-plane-1: vagrant ssh control-plane-1 -c 'hostname -I'"
echo "  2. Copie o script: scp root@<IP>:/root/join-worker.sh /root/"
echo "  3. Execute: sudo bash /root/join-worker.sh"
echo ""
echo "=== [INFO] Ou use o comando de join diretamente do output do kubeadm init ==="

########################################
# Kubectl (opcional, para debug)
########################################
echo "=== [INFO] Installing kubectl ==="
apt-get install -y -qq kubectl >/dev/null || true
apt-mark hold kubectl >/dev/null 2>&1 || true

echo "=== [INFO] Worker node ready for manual join ==="
echo "=== [INFO] ${HOSTNAME} setup completed ==="
 