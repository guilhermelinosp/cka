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

up: ## Cria o cluster completo (HAProxy + CP + Workers + HA + Addons)
	@echo "$(GREEN)[INFO] Iniciando HAProxy Load Balancer...$(NC)"
	vagrant up haproxy
	@echo "$(GREEN)[OK] HAProxy iniciado$(NC)"
	@echo "$(GREEN)[INFO] Iniciando control-plane-1...$(NC)"
	vagrant up control-plane-1
	@echo "$(GREEN)[OK] control-plane-1 iniciado$(NC)"
	@echo "$(GREEN)[INFO] Registrando control-plane-1 no HAProxy...$(NC)"
	@CP1_IP=$$(vagrant ssh control-plane-1 -- -T "hostname -I | awk '{print \$$1}'" 2>/dev/null | tr -d '\r\n'); \
	vagrant ssh haproxy -- -T "sudo /usr/local/bin/register-control-plane.sh control-plane-1 $$CP1_IP"
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
	vagrant destroy -f; rm -rf .vagrant
	@echo "$(GREEN)[OK] Cluster destruído$(NC)"

haproxy: ## Mostra status e IP do HAProxy
	@echo "$(GREEN)=== HAProxy Load Balancer ===$(NC)"
	@HAPROXY_IP=$$(vagrant ssh haproxy -- -T "hostname -I | awk '{print \$$1}'" 2>/dev/null | tr -d '\r\n'); \
	echo "IP: $$HAPROXY_IP"; \
	echo "API Server: https://$$HAPROXY_IP:6443"; \
	echo "Stats Page: http://$$HAPROXY_IP:8404/stats (admin:admin)"; \
	echo ""; \
	echo "$(YELLOW)Backends registrados:$(NC)"; \
	vagrant ssh haproxy -- -T "grep 'server control-plane' /etc/haproxy/haproxy.cfg 2>/dev/null || echo 'Nenhum backend registrado'"

longhorn: ## Mostra status do Longhorn storage
	@echo "$(GREEN)=== Longhorn Storage ===$(NC)"
	@echo ""
	@echo "$(YELLOW)StorageClasses:$(NC)"
	@kubectl get storageclass 2>/dev/null || echo "kubectl nao configurado"
	@echo ""
	@echo "$(YELLOW)Longhorn Pods:$(NC)"
	@kubectl get pods -n longhorn-system 2>/dev/null | head -15 || echo "Longhorn nao instalado"
	@echo ""
	@echo "$(YELLOW)Volumes:$(NC)"
	@kubectl get pvc -A 2>/dev/null || true
	@echo ""
	@WORKER_IP=$$(vagrant ssh worker-node-1 -- -T "hostname -I | awk '{print \$$1}'" 2>/dev/null | tr -d '\r\n'); \
	echo "$(GREEN)UI do Longhorn: http://$$WORKER_IP:30080$(NC)"

