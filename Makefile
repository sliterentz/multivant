.PHONY: help init plugin-check validate up up-blue up-green down destroy status ssh clean provision kubeconfig info

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)Multivant - Multi-Cluster Blue-Green Deployment$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

init: ## Initialize the environment
	@if [ ! -f .env ]; then \
	    echo "$(YELLOW)Creating .env file from .env.example...$(NC)"; \
	    cp .env.example .env; \
	    echo "$(GREEN)✅ .env file created$(NC)"; \
	    echo "$(YELLOW)⚠️  Please edit .env and set K3S_TOKEN$(NC)"; \
	    echo "$(YELLOW)   Generate token with: openssl rand -hex 32$(NC)"; \
	else \
	    echo "$(GREEN).env file already exists$(NC)"; \
	fi
	@mkdir -p shared scripts
	@echo "$(GREEN)✅ Directories created$(NC)"

plugin-check: ## Check and install required Vagrant plugins
	@echo "$(BLUE)Checking Vagrant plugins...$(NC)"
	@if ! vagrant plugin list | grep -q vagrant-env; then \
	    echo "$(YELLOW)Installing vagrant-env plugin...$(NC)"; \
	    vagrant plugin install vagrant-env; \
	    echo "$(GREEN)✅ vagrant-env installed$(NC)"; \
	else \
	    echo "$(GREEN)✅ vagrant-env already installed$(NC)"; \
	fi

validate: ## Validate Vagrantfile
	@echo "$(BLUE)Validating Vagrantfile...$(NC)"
	@vagrant validate
	@echo "$(GREEN)✅ Vagrantfile is valid$(NC)"

up: ## Start all VMs
	@echo "$(BLUE)Starting all VMs...$(NC)"
	vagrant up --provider=virtualbox
	@echo "$(GREEN)✅ All VMs started$(NC)"

up-blue: ## Start only blue cluster
	@echo "$(BLUE)Starting blue cluster...$(NC)"
	vagrant up blue-master --provider=virtualbox
	@for i in $$(seq 1 $$(grep NUM_WORKER_NODES .env | cut -d= -f2)); do \
	    vagrant up blue-node-$$i --provider=virtualbox; \
	done
	@echo "$(GREEN)✅ Blue cluster started$(NC)"

up-green: ## Start only green cluster
	@echo "$(BLUE)Starting green cluster...$(NC)"
	vagrant up green-master --provider=virtualbox
	@for i in $$(seq 1 $$(grep NUM_WORKER_NODES .env | cut -d= -f2)); do \
	    vagrant up green-node-$$i --provider=virtualbox; \
	done
	@echo "$(GREEN)✅ Green cluster started$(NC)"

up-shared: plugin-check ## Start only shared services
	@echo "$(BLUE)Starting shared services...$(NC)"
	@if grep -q "ENABLE_IDENTITY_PLANE=true" .env; then \
	    vagrant up identity-plane --provider=virtualbox; \
	fi
	@if grep -q "ENABLE_BUILD_PLANE=true" .env; then \
	    vagrant up build-plane --provider=virtualbox; \
	fi
	@if grep -q "ENABLE_OBSERVABILITY=true" .env; then \
	    vagrant up observability-plane --provider=virtualbox; \
	fi
	@echo "$(GREEN)✅ Shared services started$(NC)"

down: ## Halt all VMs
	@echo "$(YELLOW)Halting all VMs...$(NC)"
	vagrant halt
	@echo "$(GREEN)✅ All VMs halted$(NC)"

destroy: ## Destroy all VMs
	@echo "$(RED)Destroying all VMs...$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
	    vagrant destroy -f; \
	    echo "$(GREEN)✅ All VMs destroyed$(NC)"; \
	else \
	    echo "$(YELLOW)Cancelled$(NC)"; \
	fi

status: ## Show status of all VMs
	@echo "$(BLUE)VM Status:$(NC)"
	@vagrant status

ssh-blue-master: ## SSH into blue master
	vagrant ssh blue-master

ssh-green-master: ## SSH into green master
	vagrant ssh green-master

provision: ## Re-run provisioning
	@echo "$(BLUE)Re-provisioning all VMs...$(NC)"
	vagrant provision
	@echo "$(GREEN)✅ Provisioning completed$(NC)"

clean: ## Clean up temporary files
	@echo "$(YELLOW)Cleaning up...$(NC)"
	@rm -rf .vagrant/machines/*/virtualbox/action_provision
	@rm -rf ansible/*.retry
	@echo "$(GREEN)✅ Cleanup completed$(NC)"

kubeconfig-blue: ## Get kubeconfig for blue cluster
	@echo "$(BLUE)Fetching blue cluster kubeconfig...$(NC)"
	@vagrant ssh blue-master -c "sudo cat /etc/rancher/k3s/k3s.yaml" | \
	    sed "s/127.0.0.1/$$(grep BLUE_IP_PREFIX .env | cut -d= -f2)10/" > kubeconfig-blue.yaml
	@echo "$(GREEN)✅ Kubeconfig saved to kubeconfig-blue.yaml$(NC)"

kubeconfig-green: ## Get kubeconfig for green cluster
	@echo "$(BLUE)Fetching green cluster kubeconfig...$(NC)"
	@vagrant ssh green-master -c "sudo cat /etc/rancher/k3s/k3s.yaml" | \
	    sed "s/127.0.0.1/$$(grep GREEN_IP_PREFIX .env | cut -d= -f2)10/" > kubeconfig-green.yaml
	@echo "$(GREEN)✅ Kubeconfig saved to kubeconfig-green.yaml$(NC)"

validate: ## Validate Vagrantfile
	@echo "$(BLUE)Validating Vagrantfile...$(NC)"
	@vagrant validate
	@echo "$(GREEN)✅ Vagrantfile is valid$(NC)"

info: ## Show cluster information
	@echo "$(BLUE)Cluster Information:$(NC)"
	@echo ""
	@BLUE_IP=$$(grep BLUE_IP_PREFIX .env | cut -d= -f2 | tr -d ' '); \
	GREEN_IP=$$(grep GREEN_IP_PREFIX .env | cut -d= -f2 | tr -d ' '); \
	SHARED_IP=$$(grep SHARED_SERVICES_IP_PREFIX .env | cut -d= -f2 | tr -d ' '); \
	NUM_WORKERS=$$(grep NUM_WORKER_NODES .env | cut -d= -f2 | tr -d ' '); \
	echo "$(GREEN)Blue Cluster:$(NC)"; \
	echo "  Master: $${BLUE_IP}10"; \
	echo "  Workers: $${NUM_WORKERS} nodes ($${BLUE_IP}11 - $${BLUE_IP}1$$NUM_WORKERS)"; \
	echo ""; \
	echo "$(GREEN)Green Cluster:$(NC)"; \
	echo "  Master: $${GREEN_IP}10"; \
	echo "  Workers: $${NUM_WORKERS} nodes ($${GREEN_IP}11 - $${GREEN_IP}1$$NUM_WORKERS)"; \
	echo ""; \
	echo "$(GREEN)Shared Services:$(NC)"; \
	if grep -q "ENABLE_IDENTITY_PLANE=true" .env; then \
	    echo "  Identity Plane: $${SHARED_IP}10"; \
	fi; \
	if grep -q "ENABLE_BUILD_PLANE=true" .env; then \
	    echo "  Build Plane: $${SHARED_IP}20"; \
	fi; \
	if grep -q "ENABLE_OBSERVABILITY=true" .env; then \
	    echo "  Observability: $${SHARED_IP}30"; \
	fi

test-ruby: ## Test Ruby syntax
	@echo "$(BLUE)Testing Ruby syntax...$(NC)"
	@ruby -c Vagrantfile
	@ruby -c vagrant/config.rb
	@ruby -c vagrant/helpers.rb
	@ruby -c vagrant/provisioners.rb
	@echo "$(GREEN)✅ All Ruby files are valid$(NC)"

fix-dotenv: ## Fix dotenv plugin issue
	@echo "$(YELLOW)Fixing dotenv plugin...$(NC)"
	@vagrant plugin uninstall vagrant-dotenv 2>/dev/null || true
	@vagrant plugin install vagrant-env
	@echo "$(GREEN)✅ vagrant-env plugin installed$(NC)"