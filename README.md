# CKA Lab - Kubernetes Cluster

Ambiente de laboratorio para estudo da certificacao **CKA (Certified Kubernetes Administrator)**.

## Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                         CKA Lab Cluster                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │  VIP: x.x.x.100     │                      │
│                    │  (kube-vip)         │                      │
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

| Componente    | Quantidade | vCPU | RAM | Rede |
|---------------|------------|------|-----|------|
| Control Plane | 3          | 2    | 2GB | DHCP |
| Workers       | 6          | 1    | 1GB | DHCP |

### Stack Tecnologico

| Componente            | Versao/Config                        |
|-----------------------|--------------------------------------|
| **OS**                | Debian Bookworm 64-bit               |
| **Kubernetes**        | v1.35.0                              |
| **Container Runtime** | Containerd                           |
| **CNI**               | Cilium (kubeProxyReplacement=true)   |
| **API Server HA**     | kube-vip (VIP dinamico: x.x.x.100)   |
| **Load Balancer**     | MetalLB (L2 mode)                    |
| **Ingress**           | NGINX Ingress Controller (DaemonSet) |
| **Pod CIDR**          | 10.0.0.0/16                          |

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
├── install-addons.sh           # Instala MetalLB e NGINX Ingress
├── manifests/
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
| `make vip` | Mostra o VIP do API Server |
| `make test` | Testa o cluster com deployment nginx |
| `make test-clean` | Remove o deployment de teste |
| `make down` | Para todas as VMs (preserva dados) |
| `make resume` | Retoma VMs paradas |
| `make destroy` | Destroi todas as VMs |
| `make ssh-cp1` | SSH no control-plane-1 |

## HA com kube-vip

O cluster usa **kube-vip** para alta disponibilidade do API Server:

- **VIP dinamico**: Calculado como `x.x.x.100` baseado no IP do node
- **Leader election**: Um control-plane responde pelo VIP
- **Failover automatico**: Se o leader cair, outro assume (~5s)

```bash
# Verificar kube-vip
kubectl get pods -n kube-system | grep kube-vip

# Ver qual node tem o VIP
make vip

# Testar failover
vagrant halt control-plane-1
kubectl get nodes  # Ainda funciona!
vagrant up control-plane-1
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

# Verificar Cilium
kubectl exec -n kube-system -it ds/cilium -- cilium status

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
- [ ] Services & Networking
- [ ] Storage
- [ ] Troubleshooting

## Troubleshooting

### Nodes nao se comunicam

```bash
# Verificar conectividade
kubectl get nodes -owide
ping <NODE-IP>
```

### Cilium nao esta funcionando

```bash
# Verificar status
kubectl exec -n kube-system -it ds/cilium -- cilium status

# Ver logs
kubectl logs -n kube-system -l k8s-app=cilium
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

