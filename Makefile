# =============================================================================
# CKA Lab - Makefile
# =============================================================================
# Comandos para gerenciar o cluster Kubernetes
# =============================================================================

.PHONY: help up cp1 workers ha addons all down destroy status kubeconfig clean test

# Suprime warnings do fog-libvirt (issue hashicorp/vagrant#13544)
export RUBYOPT := -W0

# Cores para output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m

help: ## Mostra esta ajuda
	@echo "CKA Lab - Comandos disponiveis:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Uso tipico:"
	@echo "  make all        # Cria o cluster completo"
	@echo "  make down       # Para todas as VMs"
	@echo "  make destroy    # Destroi todas as VMs"

# =============================================================================
# Criacao do Cluster
# =============================================================================

start: ## Inicia o control-maaa	plane-1 (primario)
	@echo "$(GREEN)[INFO] Iniciando control-plane-1...$(NC)"
	vagrant up control-plane-1
	@echo "$(GREEN)[OK] control-plane-1 iniciado$(NC)"

kubeconfig: ## Exporta o kubeconfig para o host
	@echo "$(GREEN)[INFO] Exportando kubeconfig...$(NC)"
	./scripts/export-kubeconfig.sh

workers: ## Inicia todos os workers e faz join
	@echo "$(GREEN)[INFO] Iniciando workers...$(NC)"
	vagrant up worker-node-1 worker-node-2 worker-node-3 worker-node-4 worker-node-5 worker-node-6 --parallel
	@echo "$(GREEN)[INFO] Fazendo join dos workers...$(NC)"
	./scripts/join-workers.sh

ha: ## Inicia control-planes 2 e 3 e faz join (HA)
	@echo "$(GREEN)[INFO] Iniciando control-planes 2 e 3...$(NC)"
	vagrant up control-plane-2 control-plane-3 --parallel
	@echo "$(GREEN)[INFO] Fazendo join dos control-planes...$(NC)"
	./scripts/join-control-planes.sh

addons: ## Instala MetalLB e NGINX Ingress
	@echo "$(GREEN)[INFO] Instalando addons...$(NC)"
	./scripts/install-addons.sh

up: start kubeconfig workers ha addons ## Cria o cluster completo (CP + Workers + HA + Addons)
	@echo ""
	@echo "$(GREEN)=== Cluster CKA Lab criado com sucesso! ===$(NC)"
	@echo ""
	kubectl get nodes -owide

# =============================================================================
# Gerenciamento
# =============================================================================

status: ## Mostra o status das VMs e nodes
	@echo "$(GREEN)=== Status das VMs ===$(NC)"
	@vagrant status
	@echo ""
	@echo "$(GREEN)=== Status dos Nodes ===$(NC)"
	@kubectl get nodes -owide 2>/dev/null || echo "$(YELLOW)[WARN] kubectl nao configurado. Execute: make kubeconfig$(NC)"

resume: ## Retoma todas as VMs paradas
	@echo "$(GREEN)[INFO] Retomando VMs...$(NC)"
	vagrant up
	@echo "$(GREEN)[OK] VMs retomadas$(NC)"

down: ## Destroi todas as VMs (APAGA TUDO)
	@echo "$(RED)[WARN] Isso vai DESTRUIR todas as VMs!$(NC)"
	vagrant destroy -f
	rm -f ~/.kube/config
	@echo "$(GREEN)[OK] Cluster destruido$(NC)"

ssh-cp1: ## SSH no control-plane-1
	vagrant ssh control-plane-1

ssh-cp2: ## SSH no control-plane-2
	vagrant ssh control-plane-2

ssh-cp3: ## SSH no control-plane-3
	vagrant ssh control-plane-3

ssh-w1: ## SSH no worker-node-1
	vagrant ssh worker-node-1

