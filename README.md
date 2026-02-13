# CKA Lab - Kubernetes Cluster

Ambiente de laboratorio para estudo da certificacao **CKA (Certified Kubernetes Administrator)**.

## Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                         CKA Lab Cluster                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │      HAProxy        │                      │
│                    │  Load Balancer      │                      │
│                    │    :6443 → CP       │                      │
│                    └──────────┬──────────┘                      │
│                               │                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ control-    │  │ control-    │  │ control-    │  Control    │
│  │ plane-1     │  │ plane-2     │  │ plane-3     │  Plane (HA) │
│  │ (primary)   │  │ (join)      │  │ (join)      │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│  │worker-1 │ │worker-2 │ │worker-3 │ │worker-4 │ │worker-5 │   │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘   │
│                                                                 │
│  ┌─────────┐                                                    │
│  │worker-6 │  Workers                                           │
│  └─────────┘                                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Especificacoes

| Componente    | Quantidade | vCPU | RAM   | Rede |
|---------------|------------|------|-------|------|
| HAProxy       | 1          | 1    | 512MB | DHCP |
| Control Plane | 3          | 2    | 4GB   | DHCP |
| Workers       | 6          | 1    | 2GB   | DHCP |

### Stack Tecnologico

| Componente            | Versao/Config                        |
|-----------------------|--------------------------------------|
| **OS**                | Debian Bookworm 64-bit               |
| **Kubernetes**        | v1.35.0                              |
| **Container Runtime** | Containerd                           |
| **CNI**               | Calico (suporta NetworkPolicy)       |
| **API Server HA**     | HAProxy (Load Balancer externo)      |
| **Load Balancer**     | MetalLB (L2 mode)                    |
| **Ingress**           | NGINX Ingress Controller (DaemonSet) |
| **Storage**           | Longhorn (distributed, replicated)   |
| **Metrics**           | Metrics Server (kubectl top)         |
| **Pod CIDR**          | 192.168.0.0/16                       |

## Quick Start

### Pre-requisitos

- [Vagrant](https://www.vagrantup.com/downloads)
- [libvirt](https://libvirt.org/) + [vagrant-libvirt](https://github.com/vagrant-libvirt/vagrant-libvirt)
- kubectl instalado no host
- make

```bash
# Instalar vagrant-libvirt (Ubuntu/Debian)
sudo apt-get install -y vagrant libvirt-daemon-system make
vagrant plugin install vagrant-libvirt
```

### Usando Makefile (Recomendado)

```bash
# Ver comandos disponiveis
make help

# Criar cluster completo (control-planes + workers + addons)
make all

# Ou passo a passo:
make up        # Inicia control-plane-1 e exporta kubeconfig
make workers   # Inicia e faz join dos workers
make ha        # Inicia e faz join dos control-planes 2 e 3
make addons    # Instala MetalLB e NGINX Ingress

# Verificar status
make status

# Testar com nginx
make test

# Destruir cluster
make destroy
```

### Usando Scripts (Alternativo)

```bash
# 1. Iniciar o control-plane-1
vagrant up control-plane-1

# 2. Exportar kubeconfig
./export-kubeconfig.sh

# 3. Adicionar workers
vagrant up worker-node-1 worker-node-2 worker-node-3 worker-node-4 worker-node-5 worker-node-6
./join-workers.sh

# 4. Adicionar control-planes (HA)
vagrant up control-plane-2 control-plane-3
./join-control-planes.sh

# 5. Instalar addons
./install-addons.sh
```

## Estrutura do Projeto

```
cka/
├── Makefile                    # Comandos para gerenciar o cluster
├── Vagrantfile                 # Definicao das VMs (libvirt)
├── README.md                   # Este arquivo
├── SUGESTOES.md               # Sugestoes de melhorias
├── export-kubeconfig.sh        # Exporta kubeconfig para o host
├── join-workers.sh             # Join workers ao cluster
├── join-control-planes.sh      # Join control planes ao cluster
├── install-addons.sh           # Instala addons (Storage, LB, Ingress)
├── manifests/
│   ├── hostpath-provisioner.yaml     # HostPath Provisioner DaemonSet
│   ├── metallb-config.yaml           # IP Pool do MetalLB
│   ├── ingress-nginx-daemonset.yaml  # NGINX Ingress DaemonSet
│   └── ingress-nginx-service.yaml    # NGINX Ingress Service (LoadBalancer)
└── scripts/
    ├── common-setup.sh         # Setup comum (kernel, containerd, k8s)
    ├── control-plane-setup.sh  # Setup do control plane (kubeadm init + kube-vip)
    └── worker-setup.sh         # Setup dos workers
```

## Comandos Makefile

| Comando | Descricao |
|---------|-----------|
| `make help` | Mostra todos os comandos disponiveis |
| `make all` | Cria o cluster completo |
| `make up` | Inicia control-plane-1 e exporta kubeconfig |
| `make workers` | Inicia e faz join dos workers |
| `make ha` | Inicia e faz join dos control-planes 2 e 3 |
| `make addons` | Instala MetalLB e NGINX Ingress |
| `make status` | Mostra status das VMs e nodes |
| `make info` | Mostra informacoes detalhadas do cluster |
| `make haproxy` | Mostra o IP do HAProxy e stats |
| `make test` | Testa o cluster com deployment nginx |
| `make test-clean` | Remove o deployment de teste |
| `make down` | Para todas as VMs (preserva dados) |
| `make resume` | Retoma VMs paradas |
| `make destroy` | Destroi todas as VMs |
| `make ssh-cp1` | SSH no control-plane-1 |

## HA com HAProxy

O cluster usa **HAProxy** para alta disponibilidade do API Server:

- **Load Balancer externo**: HAProxy distribui trafego para todos os control planes
- **Health checks**: HAProxy verifica saude dos backends automaticamente
- **Failover automatico**: Se um control plane cair, o trafego vai para os outros
- **Stats page**: Interface web para monitorar o HAProxy

```bash
# Verificar status do HAProxy
vagrant ssh haproxy -- -T sudo systemctl status haproxy

# Ver stats page (acesso via browser)
# http://<haproxy-ip>:8404/stats
# Credenciais: admin:admin

# Verificar backends registrados
vagrant ssh haproxy -- -T grep "server control-plane" /etc/haproxy/haproxy.cfg

# Testar failover
vagrant halt control-plane-1
kubectl get nodes  # Ainda funciona!
vagrant up control-plane-1
```

## Storage com Longhorn

O cluster usa **Longhorn** para storage distribuido e replicado:

- **Distributed**: Dados distribuidos entre os workers
- **Replica-aware**: Replicas configuradas automaticamente baseado no numero de workers
- **Kubernetes-native**: Integrado nativamente via CSI
- **UI Web**: Interface grafica para gerenciamento

### StorageClasses Disponiveis

As replicas sao calculadas dinamicamente baseado no numero de workers:

| StorageClass     | Replicas                  | Uso                              |
|------------------|---------------------------|----------------------------------|
| `longhorn`       | workers/2 (min 2)         | Padrao, balanco entre HA e performance |
| `longhorn-ha`    | todos os workers          | Alta disponibilidade maxima      |
| `longhorn-min`   | 2                         | HA minima                        |
| `longhorn-single`| 1                         | Performance maxima (sem replica) |

**Exemplo com 6 workers:**
- `longhorn`: 3 replicas
- `longhorn-ha`: 6 replicas
- `longhorn-min`: 2 replicas
- `longhorn-single`: 1 replica

### Exemplo de Uso

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: meu-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn  # ou longhorn-ha, longhorn-min, longhorn-single
  resources:
    requests:
      storage: 1Gi
```

### Comandos Uteis

```bash
# Verificar pods do Longhorn
kubectl get pods -n longhorn-system

# Verificar volumes
kubectl get volumes.longhorn.io -n longhorn-system

# Verificar replicas
kubectl get replicas.longhorn.io -n longhorn-system

# Acessar UI do Longhorn (NodePort 30080)
# http://<worker-ip>:30080

# Verificar StorageClasses e numero de replicas
kubectl get storageclass -o custom-columns=NAME:.metadata.name,REPLICAS:.parameters.numberOfReplicas
```
# Subir control-plane-2 e control-plane-3
vagrant up control-plane-2 control-plane-3

# Fazer join dos control planes
./join-control-planes.sh
```

### 5. Instalar Addons (MetalLB + NGINX Ingress)

```bash
# Instalar MetalLB e NGINX Ingress Controller
./install-addons.sh
```

## Estrutura do Projeto

```
cka/
├── Vagrantfile                 # Definicao das VMs (libvirt)
├── README.md                   # Este arquivo
├── export-kubeconfig.sh        # Exporta kubeconfig para o host
├── join-workers.sh             # Join workers ao cluster
├── join-control-planes.sh      # Join control planes ao cluster
├── install-addons.sh           # Instala MetalLB e NGINX Ingress
├── manifests/
│   ├── metallb-config.yaml           # IP Pool do MetalLB
│   ├── ingress-nginx-daemonset.yaml  # NGINX Ingress DaemonSet
│   └── ingress-nginx-service.yaml    # NGINX Ingress Service (LoadBalancer)
└── scripts/
    ├── common-setup.sh         # Setup comum (kernel, containerd, k8s)
    ├── control-plane-setup.sh  # Setup do control plane (kubeadm init)
    └── worker-setup.sh         # Setup dos workers
```

## Comandos Uteis

```bash
# Status das VMs
vagrant status

# Exportar kubeconfig
./export-kubeconfig.sh

# Destruir e recriar todo o cluster
vagrant destroy -f && vagrant up control-plane-1
./export-kubeconfig.sh
vagrant up worker-node-1 worker-node-2 worker-node-3 worker-node-4 worker-node-5 worker-node-6
./join-workers.sh
vagrant up control-plane-2 control-plane-3
./join-control-planes.sh
./install-addons.sh

# Pausar VMs (economizar recursos)
vagrant suspend

# Retomar VMs
vagrant resume

# SSH em uma VM
vagrant ssh control-plane-1
```

## Testando o Cluster

```bash
# Verificar nodes
kubectl get nodes -owide

# Verificar pods do sistema
kubectl get pods -A

# Verificar Calico
kubectl get pods -n calico-system
kubectl get tigerastatus

# Verificar MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system

# Verificar NGINX Ingress
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# Criar um deployment de teste
kubectl create deployment nginx --image=nginx --replicas=3
kubectl expose deployment nginx --port=80 --type=LoadBalancer
kubectl get svc nginx  # Deve mostrar EXTERNAL-IP do MetalLB

# Testar acesso via LoadBalancer
curl http://<EXTERNAL-IP>
```

## Topicos CKA para Praticar

- [x] Cluster Architecture, Installation & Configuration
- [ ] Workloads & Scheduling
- [ ] Services & Networking (NetworkPolicy com Calico)
- [ ] Storage
- [ ] Troubleshooting

## Troubleshooting

### Nodes nao se comunicam

```bash
# Verificar conectividade
kubectl get nodes -owide
ping <NODE-IP>
```

### Calico nao esta funcionando

```bash
# Verificar status
kubectl get tigerastatus
kubectl get pods -n calico-system

# Ver logs
kubectl logs -n calico-system -l k8s-app=calico-node
```

### Worker nao faz join

```bash
# Verificar script de join
vagrant ssh control-plane-1 -- -T "sudo cat /root/join-worker.sh"

# Executar manualmente no worker
vagrant ssh worker-node-1 -- -T "sudo kubeadm join ..."
```

### MetalLB nao atribui IP

```bash
# Verificar IPAddressPool
kubectl get ipaddresspool -n metallb-system -oyaml

# Ver logs do speaker
kubectl logs -n metallb-system -l component=speaker
```

### NGINX Ingress sem EXTERNAL-IP

```bash
# Verificar se o service e LoadBalancer
kubectl get svc -n ingress-nginx

# Se for NodePort, aplicar o fix:
kubectl apply -f manifests/ingress-nginx-service.yaml
```

## Licenca

MIT

