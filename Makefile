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

up: ## Cria o cluster completo (CP + Workers + HA + Addons)
	@echo "$(GREEN)[INFO] Iniciando control-plane-1...$(NC)"
	vagrant up control-plane-1
	@echo "$(GREEN)[OK] control-plane-1 iniciado$(NC)"
	@echo "$(GREEN)[INFO] Exportando kubeconfig...$(NC)"
	./scripts/export-kubeconfig.sh
	@echo "$(GREEN)[INFO] Iniciando workers...$(NC)"
	vagrant up worker-node-1 worker-node-2 worker-node-3 worker-node-4 worker-node-5 worker-node-6 --parallel
	@echo "$(GREEN)[INFO] Fazendo join dos workers...$(NC)"
	./scripts/join-workers.sh
	@echo "$(GREEN)[INFO] Iniciando control-planes 2 e 3...$(NC)"
	vagrant up control-plane-2 control-plane-3 --parallel
	@echo "$(GREEN)[INFO] Fazendo join dos control-planes...$(NC)"
	./scripts/join-control-planes.sh
	@echo "$(GREEN)[INFO] Instalando addons...$(NC)"
	./scripts/install-addons.sh
	@echo ""
	@echo "$(GREEN)=== Cluster CKA Lab criado com sucesso! ===$(NC)"
	@echo ""
	kubectl get nodes -owide

down: ## Destroi todas as VMs do cluster
	@echo "$(RED)[INFO] Destruindo todas as VMs...$(NC)"
	vagrant destroy -f
	@echo "$(GREEN)[OK] Cluster destruído$(NC)"
