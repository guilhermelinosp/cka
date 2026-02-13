#!/bin/bash
set -euo pipefail

# =============================================================================
# HAProxy Load Balancer Setup para Kubernetes API Server
# =============================================================================

HOSTNAME=$(hostname)
NODE_IP=$(hostname -I | awk '{print $1}')

echo "=== [INFO] HAProxy setup on ${HOSTNAME} ==="
echo "=== [INFO] HAProxy IP: ${NODE_IP} ==="

########################################
# Locale (evita warnings de LC_ALL)
########################################
echo "=== [INFO] Configuring locale ==="

apt-get update -qq
apt-get install -y -qq locales >/dev/null
sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen
locale-gen en_US.UTF-8 >/dev/null
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

########################################
# Install HAProxy and socat
########################################
echo "=== [INFO] Installing HAProxy ==="

apt-get update -qq
apt-get install -y -qq haproxy socat >/dev/null

########################################
# HAProxy Configuration
########################################
echo "=== [INFO] Configuring HAProxy ==="

# Backup original config
cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak

cat <<'EOF' >/etc/haproxy/haproxy.cfg
#---------------------------------------------------------------------
# HAProxy Configuration for Kubernetes API Server Load Balancing
#---------------------------------------------------------------------

global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Default SSL material locations
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

    # Security settings
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 10s
    timeout client  1m
    timeout server  1m
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

#---------------------------------------------------------------------
# Stats Page (acesso via http://haproxy-ip:8404/stats)
#---------------------------------------------------------------------
frontend stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats auth admin:admin

#---------------------------------------------------------------------
# Kubernetes API Server Frontend
#---------------------------------------------------------------------
frontend kubernetes-apiserver
    bind *:6443
    mode tcp
    option tcplog
    default_backend kubernetes-apiserver-backend

#---------------------------------------------------------------------
# Kubernetes API Server Backend
#---------------------------------------------------------------------
backend kubernetes-apiserver-backend
    mode tcp
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100

    # Control Plane nodes - adicionados dinamicamente
    # CONTROL_PLANES_PLACEHOLDER

EOF

########################################
# Script para registrar control planes
########################################
cat <<'SCRIPT' >/usr/local/bin/register-control-plane.sh
#!/bin/bash
# Script para registrar um control plane no HAProxy
# Uso: register-control-plane.sh <node-name> <node-ip>

NODE_NAME=$1
NODE_IP=$2
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"

if [ -z "$NODE_NAME" ] || [ -z "$NODE_IP" ]; then
    echo "Usage: $0 <node-name> <node-ip>"
    exit 1
fi

# Verifica se o node ja esta registrado
if grep -q "server ${NODE_NAME} " "$HAPROXY_CFG"; then
    echo "Node ${NODE_NAME} already registered"
    exit 0
fi

# Adiciona o server ao backend
sed -i "/# CONTROL_PLANES_PLACEHOLDER/a\\    server ${NODE_NAME} ${NODE_IP}:6443 check" "$HAPROXY_CFG"

echo "Registered ${NODE_NAME} (${NODE_IP}) in HAProxy"

# Reload HAProxy
systemctl reload haproxy
echo "HAProxy reloaded"
SCRIPT

chmod +x /usr/local/bin/register-control-plane.sh

########################################
# Enable and Start HAProxy
########################################
echo "=== [INFO] Starting HAProxy ==="

systemctl enable haproxy
systemctl restart haproxy

########################################
# Save HAProxy IP for other nodes
########################################
echo "${NODE_IP}" > /root/haproxy-ip.txt

# Cria script helper para verificar status
cat <<'SCRIPT' >/usr/local/bin/haproxy-status.sh
#!/bin/bash
echo "=== HAProxy Status ==="
systemctl status haproxy --no-pager
echo ""
echo "=== HAProxy Stats ==="
echo "Access: http://$(hostname -I | awk '{print $1}'):8404/stats"
echo "Credentials: admin:admin"
echo ""
echo "=== Current Backend Servers ==="
grep "server control-plane" /etc/haproxy/haproxy.cfg || echo "No control planes registered yet"
SCRIPT

chmod +x /usr/local/bin/haproxy-status.sh

echo "=== [INFO] HAProxy setup completed ==="
echo "=== [INFO] HAProxy IP: ${NODE_IP} ==="
echo "=== [INFO] API Server LB: https://${NODE_IP}:6443 ==="
echo "=== [INFO] Stats Page: http://${NODE_IP}:8404/stats (admin:admin) ==="

