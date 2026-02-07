# CKA Lab - Kubernetes Cluster

Ambiente de laboratório para estudo da certificação **CKA (Certified Kubernetes Administrator)**.

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                         CKA Lab Cluster                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ control-    │  │ control-    │  │ control-    │  Control    │
│  │ plane-1     │  │ plane-2     │  │ plane-3     │  Plane (HA) │
│  │ (primary)   │  │ (manual)    │  │ (manual)    │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│  │worker-1 │ │worker-2 │ │worker-3 │ │worker-4 │ │worker-5 │   │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘   │
│                                                                 │
│  ┌─────────┐                                                    │
│  │worker-6 │  Workers (join via script helper)                  │
│  └─────────┘                                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 📋 Especificações

| Componente | Quantidade | vCPU | RAM | Rede |
|------------|------------|------|-----|------|
| Control Plane | 3 | 2 | 2GB | DHCP |
| Workers | 6 | 1 | 1GB | DHCP |

### Stack Tecnológico

| Componente | Versão/Config |
|------------|---------------|
| **OS** | Debian Bookworm 64-bit |
| **Kubernetes** | v1.35.0 |
| **Container Runtime** | Containerd |
| **CNI** | Cilium |
| **kube-proxy** | Desabilitado (Cilium assume) |
| **Pod CIDR** | 10.0.0.0/16 |

## 🚀 Quick Start

### Pré-requisitos

- [Vagrant](https://www.vagrantup.com/downloads)
- [libvirt](https://libvirt.org/) + [vagrant-libvirt](https://github.com/vagrant-libvirt/vagrant-libvirt)

```bash
# Instalar vagrant-libvirt (Ubuntu/Debian)
sudo apt-get install -y vagrant libvirt-daemon-system
vagrant plugin install vagrant-libvirt
```

### 1. Iniciar o Control Plane

```bash
# Subir o control-plane-1 (primário)
vagrant up control-plane-1

# Aguarde o provisionamento completar (~10 min)
```

### 2. Verificar o Cluster

```bash
# Acessar o control-plane-1
vagrant ssh control-plane-1

# Verificar nodes (como vagrant, kubectl já está configurado)
kubectl get nodes

# Verificar Cilium
cilium status
```

### 3. Adicionar Workers

```bash
# Subir workers
vagrant up worker-node-1 worker-node-2 worker-node-3

# Fazer join dos workers (execute no HOST, não na VM)
./join-workers.sh
```

### 4. (Opcional) Adicionar mais Control Planes

```bash
# Subir control-plane-2 e control-plane-3
vagrant up control-plane-2 control-plane-3

# Fazer join dos control planes (execute no HOST, não na VM)
./join-control-planes.sh
```

## 📂 Estrutura do Projeto

```
cka/
├── Vagrantfile              # Definição das VMs
├── README.md                # Este arquivo
├── join-workers.sh          # Script helper para join de workers
├── join-control-planes.sh   # Script helper para join de control planes
└── scripts/
    ├── common-setup.sh      # Setup comum (kernel, containerd, k8s repo)
    ├── control-plane-setup.sh  # Setup do control plane (init/join)
    └── worker-setup.sh      # Setup dos workers
```

## 🔧 Comandos Úteis

```bash
# Status das VMs
vagrant status

# Destruir e recriar
vagrant destroy -f && vagrant up

# Reprovisionar um node específico
vagrant provision control-plane-1

# Ver logs de provisioning
vagrant up --debug

# Pausar VMs (economizar recursos)
vagrant suspend

# Retomar VMs
vagrant resume
```

## 🧪 Testando o Cluster

```bash
# Acessar control-plane-1
vagrant ssh control-plane-1

# Verificar status do Cilium
sudo cilium status

# Criar um deployment de teste
sudo kubectl create deployment nginx --image=nginx --replicas=3

# Verificar pods
sudo kubectl get pods -o wide

# Expor como service
sudo kubectl expose deployment nginx --port=80 --type=NodePort

# Verificar service
sudo kubectl get svc
```

## 📚 Tópicos CKA para Praticar

- [ ] Cluster Architecture, Installation & Configuration
- [ ] Workloads & Scheduling
- [ ] Services & Networking
- [ ] Storage
- [ ] Troubleshooting

## ⚠️ Troubleshooting

### Nodes não se comunicam

```bash
# Verificar /etc/hosts
cat /etc/hosts

# Testar conectividade
ping control-plane-1
```

### Cilium não está funcionando

```bash
# Verificar status
sudo cilium status

# Ver logs
sudo kubectl logs -n kube-system -l k8s-app=cilium
```

### Worker não faz join

```bash
# Verificar script de join
cat /root/join-worker.sh

# Executar manualmente
sudo bash /root/join-worker.sh
```

## 📄 Licença

MIT

