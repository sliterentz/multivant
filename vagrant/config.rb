require 'dotenv'

module VagrantConfig
  class << self
    # Load environment variables
    def load_env
      env_file = File.join(File.dirname(__FILE__), '..', '.env')
      unless File.exist?(env_file)
        abort "❌ Error: .env file not found. Please run: make init"
      end
      
      # Load .env file manually
      File.readlines(env_file).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        
        key, value = line.split('=', 2)
        next unless key && value
        
        # Remove quotes if present
        value = value.gsub(/^["']|["']$/, '')
        ENV[key] = value unless ENV.key?(key)
      end
    end

    # Base VM Configuration
    def configure_base(config)
      config.vm.network :forwarded_port, guest: 22, host: 2522, auto_correct: true, id: "ssh"
      config.vm.box = "ubuntu/jammy64"
      config.vm.box_check_update = true

      # SSH Configuration - Enhanced timeout settings
      config.ssh.insert_key = true
      config.ssh.forward_agent = true
      config.ssh.keep_alive = true
      config.ssh.connect_timeout = 300  # Increase timeout to 5 minutes
      config.ssh.shell = "bash -c 'BASH_ENV=/etc/profile exec bash'"
      
      # Add boot timeout
      config.vm.boot_timeout = 600  # 10 minutes for boot
      config.vm.graceful_halt_timeout = 60
      
      # Disable default SSH port forwarding to avoid conflicts
      # config.vm.network :forwarded_port, guest: 22, host: 2222, id: "ssh", disabled: true

      # Synced Folders Configuration
      configure_synced_folders(config)
      
      # Configure networking for internet access
      configure_network_fix(config)
    end

    # Fix network and DNS configuration for internet access
    def configure_network_fix(config)
      config.vm.provision "shell", name: "network-fix", inline: <<-SHELL
        set -e
        
        echo "🔧 Configuring network and DNS..."
        
        # Fix DNS resolution
        echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
        echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf > /dev/null
        echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf > /dev/null
        
        # Prevent systemd-resolved from overwriting resolv.conf
        sudo systemctl stop systemd-resolved 2>/dev/null || true
        sudo systemctl disable systemd-resolved 2>/dev/null || true
        
        # Remove symlink if it exists
        if [ -L /etc/resolv.conf ]; then
          sudo rm /etc/resolv.conf
          echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
          echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf > /dev/null
        fi
        
        # Make resolv.conf immutable to prevent changes
        sudo chattr +i /etc/resolv.conf 2>/dev/null || true
        
        # Configure netplan for proper networking
        cat <<EOF | sudo tee /etc/netplan/01-netcfg.yaml > /dev/null
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        use-dns: false
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4, 1.1.1.1]
    eth1:
      dhcp4: no
      optional: true
EOF
        
        # Apply netplan configuration
        sudo netplan apply 2>/dev/null || true
        
        # Restart networking
        sudo systemctl restart systemd-networkd 2>/dev/null || true
        
        # Test internet connectivity
        echo "Testing internet connectivity..."
        if ping -c 2 8.8.8.8 > /dev/null 2>&1; then
          echo "✓ Internet connectivity established"
        else
          echo "⚠️  Warning: Internet connectivity test failed"
        fi
        
        # Test DNS resolution
        if nslookup google.com > /dev/null 2>&1; then
          echo "✓ DNS resolution working"
        else
          echo "⚠️  Warning: DNS resolution test failed"
        fi
        
        echo "✓ Network configuration complete"
      SHELL
    end

    # Wait for SSH to be ready
    def wait_for_ssh(config)
      config.vm.provision "shell", inline: <<-SHELL
        set -e
        
        echo "Waiting for SSH service to be ready..."
        
        # Wait for SSH service
        timeout=60
        elapsed=0
        until systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; do
          if [ $elapsed -ge $timeout ]; then
            echo "ERROR: SSH service failed to start within ${timeout} seconds"
            exit 1
          fi
          echo "Waiting for SSH service... ($elapsed/$timeout seconds)"
          sleep 2
          elapsed=$((elapsed + 2))
        done
        
        # Verify SSH is listening
        until netstat -tuln | grep -q ':22 '; do
          echo "Waiting for SSH to listen on port 22..."
          sleep 1
        done
        
        echo "✓ SSH service is ready and listening"
      SHELL
    end

    # Configure SSH access for WSL
    def configure_ssh_access(config, ip_address)
      if is_wsl?
        config.vm.provision "shell", name: "configure-ssh-wsl", inline: <<-SHELL
          set -e
          
          echo "🔐 Configuring SSH access for WSL..."
          
          # Ensure SSH is configured properly
          sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
          sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
          sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
          sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
          
          # Add ClientAliveInterval to keep connections alive
          if ! grep -q "ClientAliveInterval" /etc/ssh/sshd_config; then
            echo "ClientAliveInterval 60" | sudo tee -a /etc/ssh/sshd_config
            echo "ClientAliveCountMax 3" | sudo tee -a /etc/ssh/sshd_config
          fi
          
          # Restart SSH service
          sudo systemctl restart sshd || sudo systemctl restart ssh
          
          echo "✓ SSH configuration complete"
          echo "✓ You can now SSH to this node from WSL using: ssh vagrant@#{ip_address}"
          echo "   Password: vagrant"
        SHELL
      end
    end
    
    # Check if WSL is using mirrored networking mode
    def is_wsl_mirrored?
      return false unless is_wsl?
      
      # Check WSL configuration
      wsl_config = '/mnt/c/Users/' + ENV['USER'] + '/.wslconfig'
      
      if File.exist?(wsl_config)
        config_content = File.read(wsl_config)
        return config_content.include?('networkingMode=mirrored')
      end
      
      # Default to false if config doesn't exist
      false
    rescue
      false
    end

    # Detect WSL environment
    def is_wsl?
      ENV['WSL_DISTRO_NAME'] != nil || 
        (File.exist?('/proc/version') && File.read('/proc/version').include?('microsoft'))
    end

        # Get WSL network interface for VirtualBox
    def wsl_vbox_interface
      return nil unless is_wsl?
      
      # Try to find the interface connected to VirtualBox Host-Only network
      interfaces = `ip -o link show`.split("\n")
      
      interfaces.each do |line|
        if line.include?('eth1') || line.include?('vEthernet')
          interface_name = line.split(':')[1].strip
          return interface_name
        end
      end
      
      'eth1' # Default fallback
    rescue
      'eth1'
    end

    # Configure SSH access for WSL
    def configure_ssh_access(node, ip_address)
      return unless is_wsl?
      
      node.vm.provision "shell", run: "always", privileged: true, inline: <<-SHELL
        set -e
        
        echo "🔧 Configuring SSH access for WSL..."
        
        # Ensure SSH server is installed and running
        if ! command -v sshd &> /dev/null; then
          apt-get update -qq
          apt-get install -y openssh-server
        fi
        
        # Configure SSH for better connectivity from WSL
        mkdir -p /etc/ssh/sshd_config.d
        
        cat > /etc/ssh/sshd_config.d/99-wsl-access.conf <<'EOF'
# WSL Access Configuration
ListenAddress 0.0.0.0
ListenAddress #{ip_address}
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication yes
UseDNS no
GSSAPIAuthentication no
ClientAliveInterval 60
ClientAliveCountMax 5
TCPKeepAlive yes
EOF
        
        # Restart SSH service
        systemctl restart ssh || systemctl restart sshd || service ssh restart
        
        # Ensure SSH starts on boot
        systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
        
        # Verify SSH is listening
        if ss -tlnp | grep -q ':22'; then
          echo "✅ SSH is listening on port 22"
        else
          echo "⚠️  Warning: SSH may not be listening properly"
        fi
        
        # Add firewall rule if ufw is active
        if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
          ufw allow 22/tcp
          echo "✅ Firewall rule added for SSH"
        fi
        
        echo "✅ SSH access configured for WSL"
      SHELL
    end

    # Print WSL-specific warnings and information
    def print_wsl_info
      return unless is_wsl?
      
      puts "\n" + "="*80
      puts "WSL ENVIRONMENT DETECTED"
      puts "="*80
      
      if is_wsl_mirrored?
        puts "⚠️  WSL Mirrored Networking Mode detected"
        puts "   Special network configuration will be applied"
      end
      
      puts "\n📋 WSL Network Information:"
      puts "   Interface: #{wsl_vbox_interface}"
      
      # Check if fix script has been run
      vbox_route = `ip route show | grep "#{shared_services_ip_prefix}"`.strip
      
      if vbox_route.empty?
        puts "\n⚠️  WARNING: VirtualBox network route not configured!"
        puts "   Run: bash scripts/fix-wsl-vbox-network.sh"
      else
        puts "   ✅ VirtualBox network route configured"
      end
      
      puts "\n💡 Tips for WSL:"
      puts "   • SSH connectivity may take longer to establish"
      puts "   • Run 'bash scripts/test-wsl-ssh-connectivity.sh' to verify connections"
      puts "   • Network routes are lost after WSL restart"
      puts "="*80 + "\n"
    end

    # def is_wsl_mirrored?
    #   if is_wsl?
    #     # Try Windows user profile path first
    #     windows_home = `cmd.exe /c "echo %USERPROFILE%" 2>/dev/null`.strip.gsub('\\', '/')
        
    #     # Convert Windows path to WSL path if needed
    #     if windows_home && !windows_home.empty?
    #       wsl_path = `/usr/bin/wslpath "#{windows_home}" 2>/dev/null`.strip
    #       wslconfig_path = File.join(wsl_path, '.wslconfig') if wsl_path && !wsl_path.empty?
    #     end
        
    #     # Fallback to direct path
    #     wslconfig_path ||= '/mnt/c/Users/' + ENV['USER'] + '/.wslconfig'
        
    #     if File.exist?(wslconfig_path)
    #       content = File.read(wslconfig_path)
    #       # Check for mirrored mode in [wsl2] section
    #       return content.match?(/\[wsl2\].*networkingMode\s*=\s*mirrored/m) ||
    #              content.match?(/networkingMode\s*=\s*mirrored/)
    #     end
    #   end
    #   false
    # rescue => e
    #   puts "⚠️  Warning: Could not detect WSL mirrored mode: #{e.message}"
    #   false
    # end

    def windows_host_ip
      if is_wsl?
        `ip route show | grep -i default | awk '{ print $3}'`.strip
      else
        nil
      end
    end

    # Cluster Configuration
    def num_worker_nodes
      ENV.fetch('NUM_WORKER_NODES', 1).to_i
    end

    def vm_memory
      ENV.fetch('VM_MEMORY', 2048).to_i
    end

    def vm_cpus
      ENV.fetch('VM_CPUS', 2).to_i
    end

    # Control Plane Configuration
    def control_plane_memory
      ENV.fetch('CONTROL_PLANE_MEMORY', 4096).to_i
    end

    def control_plane_cpus
      ENV.fetch('CONTROL_PLANE_CPUS', 2).to_i
    end

    # Data Plane Configuration
    def data_plane_memory
      ENV.fetch('DATA_PLANE_MEMORY', 2048).to_i
    end

    def data_plane_cpus
      ENV.fetch('DATA_PLANE_CPUS', 2).to_i
    end

    # Build Plane Configuration
    def build_plane_memory
      ENV.fetch('BUILD_PLANE_MEMORY', 4096).to_i
    end

    def build_plane_cpus
      ENV.fetch('BUILD_PLANE_CPUS', 2).to_i
    end

    # Observability Plane Configuration
    def observability_memory
      ENV.fetch('OBSERVABILITY_MEMORY', 4096).to_i
    end

    def observability_cpus
      ENV.fetch('OBSERVABILITY_CPUS', 2).to_i
    end

    # Identity Plane Configuration
    def identity_plane_memory
      ENV.fetch('IDENTITY_PLANE_MEMORY', 2048).to_i
    end

    def identity_plane_cpus
      ENV.fetch('IDENTITY_PLANE_CPUS', 2).to_i
    end

    # Network Configuration
    def blue_ip_prefix
      prefix = ENV.fetch('BLUE_IP_PREFIX', "192.168.56.")
      validate_ip_range(prefix)
      prefix
    end

    def green_ip_prefix
      prefix = ENV.fetch('GREEN_IP_PREFIX', "192.168.57.")
      validate_ip_range(prefix)
      prefix
    end

    def shared_services_ip_prefix
      prefix = ENV.fetch('SHARED_SERVICES_IP_PREFIX', "192.168.58.")
      validate_ip_range(prefix)
      prefix
    end

    # Port Configuration
    def host_port_prefix_blue
      ENV.fetch('HOST_PORT_PREFIX_BLUE', "81")
    end

    def host_port_prefix_green
      ENV.fetch('HOST_PORT_PREFIX_GREEN', "82")
    end

    # Security
    def k3s_token
      ENV.fetch('K3S_TOKEN') do
        abort "K3S_TOKEN is not set in your .env file. Please define it."
      end
    end

    # Feature Flags
    def enable_observability?
      ENV.fetch('ENABLE_OBSERVABILITY', 'true') == 'true'
    end

    def enable_identity_plane?
      ENV.fetch('ENABLE_IDENTITY_PLANE', 'false') == 'true'
    end

    def enable_build_plane?
      ENV.fetch('ENABLE_BUILD_PLANE', 'true') == 'true'
    end

    # Ansible Configuration
    def ansible_verbose?
      ENV.fetch('ANSIBLE_VERBOSE', 'false') == 'true'
    end

    # Print Configuration
    def print_configuration
      return if defined?($config_printed)
      
      puts "=" * 80
      puts "🚀 Multivant Configuration"
      puts "=" * 80
      puts "Environment: #{is_wsl? ? 'WSL' : 'Native'}"
      puts "WSL Mirrored Mode: #{is_wsl_mirrored? ? 'Yes' : 'No'}"
      puts "Windows Host IP: #{windows_host_ip}" if windows_host_ip
      puts "Blue Cluster IP Range: #{blue_ip_prefix}x"
      puts "Green Cluster IP Range: #{green_ip_prefix}x"
      puts "Shared Services IP Range: #{shared_services_ip_prefix}x"
      puts "Worker Nodes per Cluster: #{num_worker_nodes}"
      puts "Observability: #{enable_observability? ? 'Enabled' : 'Disabled'}"
      puts "Identity Plane: #{enable_identity_plane? ? 'Enabled' : 'Disabled'}"
      puts "Build Plane: #{enable_build_plane? ? 'Enabled' : 'Disabled'}"
      puts "=" * 80
      
      $config_printed = true
    end

    private

    def validate_ip_range(ip_prefix)
      allowed_prefixes = ["192.168.56.", "192.168.57.", "192.168.58.", "192.168.59.", 
                          "192.168.60.", "192.168.61.", "192.168.62.", "192.168.63."]
      
      unless allowed_prefixes.include?(ip_prefix)
        abort <<-ERROR
        
        ❌ Invalid IP range detected!
        
        VirtualBox only allows host-only networks in the range: 192.168.56.0/21
        (192.168.56.0 - 192.168.63.255)
        
        Current IP prefix: #{ip_prefix}
        
        Please update your .env file with allowed IP ranges:
        
        BLUE_IP_PREFIX=192.168.56.
        GREEN_IP_PREFIX=192.168.57.
        SHARED_SERVICES_IP_PREFIX=192.168.58.
        
        ERROR
      end
    end

    def configure_synced_folders(config)
      if is_wsl?
        # Disable default vagrant folder sync for WSL
        config.vm.synced_folder ".", "/vagrant", disabled: true
        
        # Use rsync for WSL
        config.vm.synced_folder ".", "/vagrant", 
          type: "rsync",
          rsync__exclude: ['.git/', '.vagrant/', 'shared/', 'scripts/'],
          rsync__args: ["--verbose", "--archive", "--delete", "-z", "--copy-links", "--timeout=300"],
          rsync__auto: false
        
        # Scripts folder with rsync
        config.vm.synced_folder "./scripts", "/vagrant_scripts",
          type: "rsync",
          rsync__exclude: ['.git/'],
          rsync__args: ["--verbose", "--archive", "--delete", "-z", "--timeout=300"],
          rsync__auto: false
        
          # Add provision to fix permissions after rsync
        config.vm.provision "shell", name: "fix-permissions", inline: <<-SHELL
          sudo chown -R vagrant:vagrant /vagrant /vagrant_scripts 2>/dev/null || true
          sudo chmod -R 755 /vagrant_scripts 2>/dev/null || true
        SHELL
      else
        # For non-WSL environments
        config.vm.synced_folder "./scripts", "/vagrant_scripts", 
          create: true,
          owner: "vagrant", 
          group: "vagrant"
        
        config.vm.synced_folder "./shared", "/vagrant_shared", 
          create: true, 
          owner: "vagrant", 
          group: "vagrant"
      end
    end
  end
end

# Load environment on module load
VagrantConfig.load_env