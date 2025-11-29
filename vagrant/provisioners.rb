module VagrantProvisioners
  class << self
    # Base system provisioning
    def provision_base_system(node, hostname, ip_address)
      node.vm.provision "shell", name: "base-system", inline: <<-SHELL
        set -e
        
        echo "================================================"
        echo "🔧 Configuring Base System: #{hostname}"
        echo "================================================"
        
        # Set hostname
        hostnamectl set-hostname #{hostname}
        
        # Update /etc/hosts
        sed -i '/#{hostname}/d' /etc/hosts
        echo "#{ip_address} #{hostname}" | tee -a /etc/hosts
        echo "127.0.0.1 localhost" | tee -a /etc/hosts
        
        # Disable swap
        swapoff -a
        sed -i '/swap/d' /etc/fstab
        
        # Load kernel modules
        cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
        
        modprobe overlay
        modprobe br_netfilter
        
        # Sysctl params
        cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
        
        sysctl --system
        
        # Update system
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq \
          curl \
          wget \
          git \
          vim \
          htop \
          net-tools \
          dnsutils \
          iputils-ping \
          ca-certificates \
          gnupg \
          lsb-release \
          software-properties-common \
          apt-transport-https
        
        # Configure DNS
        if ! grep -q "8.8.8.8" /etc/resolv.conf; then
          echo "nameserver 8.8.8.8" >> /etc/resolv.conf
          echo "nameserver 8.8.4.4" >> /etc/resolv.conf
        fi
        
        echo "✅ Base system configured"
      SHELL
    end

    # K3s prerequisites
    def provision_k3s_prerequisites(node, node_type)
      node.vm.provision "shell", name: "k3s-prerequisites", inline: <<-SHELL
        set -e
        
        echo "================================================"
        echo "🔧 Installing K3s Prerequisites (#{node_type})"
        echo "================================================"
        
        # Install required packages
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq \
          curl \
          iptables \
          conntrack \
          socat \
          ethtool
        
        # Disable firewall
        systemctl stop ufw 2>/dev/null || true
        systemctl disable ufw 2>/dev/null || true
        
        echo "✅ K3s prerequisites installed"
      SHELL
    end

    # Ansible provisioning
    def provision_ansible(node, playbook, groups, extra_vars = {})
      # Check if Ansible is available
      ansible_available = system("command -v ansible-playbook > /dev/null 2>&1")
      
      if ansible_available
        node.vm.provision "ansible" do |ansible|
          ansible.playbook = playbook
          ansible.groups = groups
          ansible.extra_vars = extra_vars
          ansible.verbose = ENV['ANSIBLE_VERBOSE'] || false
          ansible.compatibility_mode = "2.0"
          
          # Use raw SSH arguments for better compatibility
          ansible.raw_ssh_args = [
            '-o StrictHostKeyChecking=no',
            '-o UserKnownHostsFile=/dev/null',
            '-o IdentitiesOnly=yes'
          ]
        end
      else
        puts "⚠️  Ansible not found, skipping Ansible provisioning"
        puts "   Install Ansible: sudo apt-get install ansible"
      end
    end

    # Provision shared service
    def provision_shared_service(node, service_type, extra_vars = {})
      node.vm.provision "shell", name: "#{service_type}-setup", inline: <<-SHELL
        set -e
        
        echo "================================================"
        echo "🔧 Setting up #{service_type}"
        echo "================================================"
        
        # Create service directories
        mkdir -p /opt/#{service_type}
        mkdir -p /var/log/#{service_type}
        
        # Install Docker if needed
        if ! command -v docker &> /dev/null; then
          echo "Installing Docker..."
          curl -fsSL https://get.docker.com -o get-docker.sh
          sh get-docker.sh
          usermod -aG docker vagrant
          systemctl enable docker
          systemctl start docker
          rm get-docker.sh
        fi
        
        echo "✅ #{service_type} base setup completed"
      SHELL
    end

    # Verify K3s installation
    def verify_k3s_installation(node, node_type)
      node.vm.provision "shell", name: "verify-k3s", run: "never", inline: <<-SHELL
        set -e
        
        echo "================================================"
        echo "🔍 Verifying K3s Installation (#{node_type})"
        echo "================================================"
        
        # Wait for K3s to be ready
        echo "Waiting for K3s to be ready..."
        timeout=300
        elapsed=0
        
        while [ $elapsed -lt $timeout ]; do
          if systemctl is-active --quiet k3s || systemctl is-active --quiet k3s-agent; then
            echo "✅ K3s service is running"
            break
          fi
          sleep 5
          elapsed=$((elapsed + 5))
        done
        
        if [ $elapsed -ge $timeout ]; then
          echo "❌ K3s service failed to start within timeout"
          exit 1
        fi
        
        # Check node status for master
        if [ "#{node_type}" = "master" ]; then
          echo "Checking cluster status..."
          sleep 10
          
          if kubectl get nodes &> /dev/null; then
            echo "✅ Kubectl is working"
            kubectl get nodes
          else
            echo "⚠️  Kubectl not ready yet"
          fi
        fi
        
        echo "✅ K3s verification completed"
      SHELL
    end
  end
end