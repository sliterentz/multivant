module VagrantHelpers
  class << self
    # WSL Detection
    def is_wsl?
      ENV['WSL_DISTRO_NAME'] != nil
    end

    # Configure VM Provider
    def configure_vm_provider(config, memory, cpus, vm_name = nil)
      # VirtualBox Provider
      config.vm.provider "virtualbox" do |vb|
        vb.name = vm_name if vm_name
        vb.memory = memory
        vb.cpus = cpus
        vb.gui = false
        vb.linked_clone = true

        # Basic optimizations
        vb.customize ["modifyvm", :id, "--uartmode1", "disconnected"]
        
        # Network adapter configuration - ensure proper order
        # Adapter 1: NAT (for SSH and internet access)
        vb.customize ["modifyvm", :id, "--nictype1", "82540EM"]
        vb.customize ["modifyvm", :id, "--cableconnected1", "on"]
        
        # Adapter 2: Host-Only (for inter-VM communication)
        vb.customize ["modifyvm", :id, "--nictype2", "82540EM"]
        vb.customize ["modifyvm", :id, "--cableconnected2", "on"]

        # DNS and network optimizations
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
        vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
        vb.customize ["modifyvm", :id, "--ioapic", "on"]

        # Performance optimizations
        vb.customize ["modifyvm", :id, "--paravirtprovider", "kvm"]
        vb.customize ["modifyvm", :id, "--nestedpaging", "on"]
        vb.customize ["modifyvm", :id, "--largepages", "on"]
        vb.customize ["modifyvm", :id, "--vtxvpid", "on"]
        vb.customize ["modifyvm", :id, "--hwvirtex", "on"]
        
        # WSL-specific optimizations
        if is_wsl?
          vb.customize ["modifyvm", :id, "--uart1", "0x3F8", "4"]
          vb.customize ["modifyvm", :id, "--uartmode1", "disconnected"]
        end
      end

      # Hyper-V Provider
      config.vm.provider "hyperv" do |hv|
        hv.memory = memory
        hv.cpus = cpus
        hv.vmname = vm_name if vm_name
        hv.linked_clone = true
        hv.enable_virtualization_extensions = true
        hv.enable_checkpoints = false
      end
    end
    
    # Configure SSH settings
    def configure_ssh(node)
      # Increase boot timeout for slower systems
      node.vm.boot_timeout = 600
      
      # SSH configuration
      node.ssh.insert_key = true
      node.ssh.forward_agent = false # Disable to avoid ssh-agent issues
      node.ssh.keep_alive = true
      
      # Connection timeouts
      node.ssh.connect_timeout = 300  # 5 minutes
      node.ssh.guest_port = 22

      # SSH extra arguments - disable problematic features
      node.ssh.extra_args = [
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        "-o", "IdentitiesOnly=yes",
        "-o", "ServerAliveInterval=60",
        "-o", "ServerAliveCountMax=5",
        "-o", "ConnectTimeout=300"
      ]
     # For WSL environments
      if VagrantConfig.is_wsl_mirrored?
        node.ssh.shell = "bash -l"
        node.ssh.sudo_command = "sudo -E -H %c"
      end
    end
    
    # Configure Network - FIXED ORDER
    def configure_network(node, ip_address, hostname)
      # CRITICAL: Private network MUST be configured AFTER provider
      # This ensures it becomes eth1, not eth0
      
      if VagrantConfig.is_wsl_mirrored?
        # For WSL Mirrored Mode: Use Host-Only network on adapter 2
        node.vm.network "private_network", 
          ip: ip_address,
          virtualbox__intnet: false,
          auto_config: true,
          nic_type: "82540EM"
        
        # WSL-specific network setup
        node.vm.provision "shell", run: "always", inline: <<-SHELL
          set -e
          
          echo "🔧 Configuring network for WSL Mirrored Mode..."
          
          # Wait for network interfaces to be ready
          sleep 3
          
          # Ensure eth1 (private network) is up and configured
          if ip link show eth1 >/dev/null 2>&1; then
            ip link set eth1 up
            
            # Check if IP is already assigned
            if ! ip addr show eth1 | grep -q "#{ip_address}"; then
              ip addr flush dev eth1
              ip addr add #{ip_address}/24 dev eth1
            fi
            
            echo "✅ Private network configured: #{ip_address}"
          else
            echo "⚠️  Warning: eth1 not found"
          fi
          
          # Ensure DNS resolution works
          if ! grep -q "8.8.8.8" /etc/resolv.conf; then
            echo "nameserver 8.8.8.8" >> /etc/resolv.conf
            echo "nameserver 8.8.4.4" >> /etc/resolv.conf
          fi
          
          # Update /etc/hosts
          sed -i '/#{hostname}/d' /etc/hosts
          echo "#{ip_address} #{hostname}" >> /etc/hosts
          
          # Ensure SSH is running and accessible
          systemctl enable ssh 2>/dev/null || true
          systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null || true
          
          echo "✅ Network configuration complete"
        SHELL
      else
        # Standard private network for non-WSL environments
        node.vm.network "private_network", 
          ip: ip_address,
          virtualbox__intnet: false,
          auto_config: true
        
        # Standard network setup
        node.vm.provision "shell", run: "always", inline: <<-SHELL
          set -e
          
          echo "🔧 Configuring network..."
          
          # Update /etc/hosts
          sed -i '/#{hostname}/d' /etc/hosts
          echo "#{ip_address} #{hostname}" >> /etc/hosts
          
          # Ensure DNS resolution
          if ! grep -q "8.8.8.8" /etc/resolv.conf; then
            echo "nameserver 8.8.8.8" >> /etc/resolv.conf
            echo "nameserver 8.8.4.4" >> /etc/resolv.conf
          fi
          
          echo "✅ Network configuration complete"
        SHELL
      end
    end

    # Configure Port Forwarding (Consistent Implementation)
    def configure_port_forwarding(node, ports, prefix = nil)
      ports.each do |service_name, port_config|
        guest_port = port_config[0]
        base_port = port_config[1]
        
        if prefix
          # For prefixed ports, calculate: prefix * 1000 + base_port
          # This ensures unique host ports across clusters while staying within valid range
          # Example: prefix 81, base 80 -> 81080 (invalid, too large)
          # Better: prefix 81, base 80 -> 8180
          host_port = (prefix.to_s[0..1].to_i * 100) + base_port
        else
          host_port = base_port
        end
        
        # Ensure port is in valid range (1024-65535)
        host_port = [host_port, 65535].min
        host_port = [host_port, 1024].max

        node.vm.network "forwarded_port", 
          guest: guest_port, 
          host: host_port, 
          auto_correct: true,
          id: "#{service_name.downcase.gsub(' ', '_')}_#{guest_port}"
        
        puts "  📡 #{service_name}: localhost:#{host_port} -> #{guest_port}"
      end
    end

    # Verify network connectivity
    def verify_network(node, hostname, ip_address)
      node.vm.provision "shell", run: "once", inline: <<-SHELL
        echo "🔍 Verifying network configuration for #{hostname}..."
        
        # Check interfaces
        echo "Network interfaces:"
        ip addr show
        
        # Check routes
        echo -e "\nRouting table:"
        ip route
        
        # Check if we can reach the internet
        echo -e "\nTesting internet connectivity..."
        if ping -c 2 8.8.8.8 > /dev/null 2>&1; then
          echo "✅ Internet connectivity: OK"
        else
          echo "⚠️  Internet connectivity: FAILED"
        fi
        
        # Check if private network is configured
        echo -e "\nTesting private network..."
        if ip addr show eth1 | grep -q "#{ip_address}"; then
          echo "✅ Private network (#{ip_address}): OK"
        else
          echo "⚠️  Private network (#{ip_address}): FAILED"
        fi
        
        # Check SSH service
        echo -e "\nSSH service status:"
        systemctl status sshd 2>/dev/null || service ssh status 2>/dev/null || echo "SSH service check skipped"
        
        echo -e "\n✅ Network verification complete for #{hostname}"
      SHELL
    end    

    # Fix SSH connectivity issues
    def fix_ssh_connectivity(node, hostname)
      node.vm.provision "shell", run: "once", privileged: true, inline: <<-SHELL
        set -e
        
        echo "🔧 Fixing SSH connectivity for #{hostname}..."
        
        # Ensure SSH is installed and configured
        apt-get update -qq
        apt-get install -y openssh-server
        
        # Configure SSH daemon for better connectivity
        cat > /etc/ssh/sshd_config.d/99-vagrant.conf <<'EOF'
# Vagrant SSH Configuration
Port 22
ListenAddress 0.0.0.0
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
UseDNS no
GSSAPIAuthentication no
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
        
        # Restart SSH service
        systemctl restart ssh || systemctl restart sshd
        
        # Ensure SSH starts on boot
        systemctl enable ssh || systemctl enable sshd
        
        echo "✅ SSH connectivity fixed for #{hostname}"
      SHELL
    end

    # Configure Shared Service Node
    def configure_shared_service_node(node, name:, ip:, memory:, cpus:, ports:, node_type:, extra_vars: {})
      puts "\n🔧 Configuring #{name}..."
      
      node.vm.hostname = name

      # 1. SSH Configuration
      configure_ssh(node)
      
      # 2. VM Provider Configuration
      configure_vm_provider(node, memory, cpus, name)
      
      # 3. Network Configuration (after SSH and provider)
      configure_network(node, ip, name)
      
      # 4. Port Forwarding
      configure_port_forwarding(node, ports)
      
      # 5. Verify Network
      verify_network(node, name, ip)
      
      # 6. Base Provisioning
      VagrantProvisioners.provision_base_system(node, name, ip)
      
      # 7. Ansible Provisioning
      ansible_groups = {
        "shared_services" => [name],
        node_type => [name]
      }
      
      ansible_extra_vars = {
        node_type: node_type,
        "#{node_type.gsub('-', '_')}_ip": ip,
        k3s_token: VagrantConfig.k3s_token
      }.merge(extra_vars)
      
      VagrantProvisioners.provision_ansible(
        node,
        "ansible/playbook.yml",
        ansible_groups,
        ansible_extra_vars
      )
    end

    # Configure K3s Master Node
    def configure_k3s_master_node(node, cluster_name:, hostname:, ip:, memory:, cpus:, port_prefix:)
      puts "\n🎯 Configuring #{cluster_name} cluster master: #{hostname}..."
      
      node.vm.hostname = hostname
      
      # 1. SSH Configuration FIRST
      configure_ssh(node)

      # 2. VM Provider Configuration
      configure_vm_provider(node, memory, cpus, hostname)
            
      # 3. Network Configuration (after SSH and provider)
      configure_network(node, ip, hostname)
      
      # 4. Port Forwarding for K3s Master
      master_ports = {
        "HTTP" => [80, 80],
        "HTTPS" => [443, 443],
        "Traefik Dashboard" => [9000, 900],
        "K3s API" => [6443, 6443]
      }
      configure_port_forwarding(node, master_ports, port_prefix)
      
      # 5. Verify Network
      verify_network(node, hostname, ip)
      
      # 6. Base Provisioning
      VagrantProvisioners.provision_base_system(node, hostname, ip)
      
      # 7. K3s Master Specific Provisioning
      VagrantProvisioners.provision_k3s_prerequisites(node, "master")
      
      # 8. Ansible Provisioning with K3s Cluster Group
      ansible_groups = {
        "masters" => [hostname],
        "#{cluster_name}_cluster" => [hostname],
        "control_plane" => [hostname],
        "k3s_cluster" => [hostname],
        "k3s_master" => [hostname]
      }
      
      ansible_extra_vars = {
        k3s_token: VagrantConfig.k3s_token,
        cluster_name: cluster_name,
        cluster_type: "production",
        node_type: "control-plane",
        master_ip: ip,
        observability_ip: "#{VagrantConfig.shared_services_ip_prefix}30",
        identity_ip: "#{VagrantConfig.shared_services_ip_prefix}10",
        build_ip: "#{VagrantConfig.shared_services_ip_prefix}20",
        enable_observability: VagrantConfig.enable_observability?,
        enable_identity_plane: VagrantConfig.enable_identity_plane?,
        enable_build_plane: VagrantConfig.enable_build_plane?
      }
      
      VagrantProvisioners.provision_ansible(
        node,
        "ansible/playbook.yml",
        ansible_groups,
        ansible_extra_vars
      )
      
      # 9. Post-installation verification
      VagrantProvisioners.verify_k3s_installation(node, "master")
    end

    # Configure K3s Worker Node
    def configure_k3s_worker_node(node, cluster_name:, hostname:, worker_number:, ip:, master_ip:, memory:, cpus:, port_prefix: nil)
      puts "\n🔧 Configuring #{cluster_name} cluster worker: #{hostname}..."
      
      node.vm.hostname = hostname

      # 1. SSH Configuration FIRST
      configure_ssh(node)
      
      # 2. VM Provider Configuration
      configure_vm_provider(node, memory, cpus, hostname)
      
      # 3. Network Configuration (after SSH and provider)
      configure_network(node, ip, hostname)

      # 4. Port Forwarding for K3s Worker (optional, for NodePort services)
      if port_prefix
        # Calculate unique ports for each worker
        # Format: base_port + (prefix_offset * 100) + worker_number
        # Blue (prefix 81): 30180, 30181, 30182... and 30380, 30381, 30382...
        # Green (prefix 82): 30280, 30281, 30282... and 30480, 30481, 30482...
        prefix_digit = port_prefix.to_s[-1].to_i  # Get last digit (1 for 81, 2 for 82)
        
        worker_ports = {
          "NodePort HTTP" => [30080, 30000 + (prefix_digit * 100) + worker_number],
          "NodePort HTTPS" => [30443, 30200 + (prefix_digit * 100) + worker_number]
        }
        configure_port_forwarding(node, worker_ports, nil)  # Pass nil since we already calculated the ports
      end

      # 5. Verify Network
      verify_network(node, hostname, ip)
      
      # 6. Base Provisioning
      VagrantProvisioners.provision_base_system(node, hostname, ip)
      
      # 7. K3s Worker Specific Provisioning
      VagrantProvisioners.provision_k3s_prerequisites(node, "worker")
      
      # Ansible Provisioning with K3s Cluster Group
      ansible_groups = {
        "workers" => [hostname],
        "#{cluster_name}_cluster" => [hostname],
        "data_plane" => [hostname],
        "k3s_cluster" => [hostname],
        "k3s_worker" => [hostname]
      }
      
      ansible_extra_vars = {
        k3s_token: VagrantConfig.k3s_token,
        cluster_name: cluster_name,
        cluster_type: "production",
        node_type: "data-plane",
        master_ip: master_ip,
        worker_ip: ip,
        observability_ip: "#{VagrantConfig.shared_services_ip_prefix}30",
        identity_ip: "#{VagrantConfig.shared_services_ip_prefix}10",
        enable_observability: VagrantConfig.enable_observability?,
        enable_identity_plane: VagrantConfig.enable_identity_plane?
      }
      
      VagrantProvisioners.provision_ansible(
        node,
        "ansible/playbook.yml",
        ansible_groups,
        ansible_extra_vars
      )
      
      # 9. Post-installation verification
      VagrantProvisioners.verify_k3s_installation(node, "worker")
    end
  end
end