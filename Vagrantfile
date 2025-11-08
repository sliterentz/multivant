# -*- Multicluster Blue Green Deployment With Vagrant -*-

# Meload environment variables dari .env file menggunakan dotenv yang di install vagrant plugin
unless Vagrant.has_plugin?("dotenv")
  abort "The 'dotenv' vagrant plugin is not installed. Please run: vagrant plugin install dotenv"
end
require 'dotenv'
Dotenv.load

# Konfigurasi Cluster
# Ubah nilai di bawah ini sesuai kebutuhan Anda
$num_worker_nodes = ENV.fetch('NUM_WORKER_NODES', 1).to_i # Jumlah worker node per cluster (blue/green)
$vm_memory = ENV.fetch('VM_MEMORY', 2048).to_i    # Memori per VM dalam MB
$vm_cpus = ENV.fetch('VM_CPUS', 2).to_i         # Jumlah CPU per VM

# Konfigurasi Jaringan
$blue_ip_prefix = ENV.fetch('BLUE_IP_PREFIX', "192.168.50.")
$green_ip_prefix = ENV.fetch('GREEN_IP_PREFIX', "192.168.51.")
$host_port_prefix_blue = ENV.fetch('HOST_PORT_PREFIX_BLUE', "81")
$host_port_prefix_green = ENV.fetch('HOST_PORT_PREFIX_GREEN', "82")

# Security
$k3s_token = ENV.fetch('K3S_TOKEN') do
  abort "K3S_TOKEN is not set in your .env file. Please define it."
end # Token untuk join worker node

Vagrant.configure("2") do |config|
  # Gunakan box Ubuntu 22.04 LTS (Jammy Jellyfish)
  config.vm.box = "ubuntu/jammy64"
  
  # Sinkronisasi folder script ke semua node
  config.vm.synced_folder "./scripts", "/vagrant_scripts", disabled: false

  # Pengaturan default untuk provider VirtualBox
  config.vm.provider "virtualbox" do |vb|
    vb.memory = $vm_memory
    vb.cpus = $vm_cpus
  end

  # Fungsi untuk provisioning K3s master
  def provision_k3s_master(node, ip, cluster_name)
    node.vm.provision "shell", inline: <<-SHELL
      echo "Disabling swap..."
      sudo swapoff -a
      sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

      echo "Installing K3s master..."
      export INSTALL_K3S_EXEC="server --node-ip=#{ip} --flannel-iface=enp0s8 --bind-address=#{ip} --advertise-address=#{ip} --tls-san #{ip}"
      curl -sfL https://get.k3s.io | K3S_TOKEN="#{$k3s_token}" sh -
      
      echo "Waiting for K3s to be ready..."
      sleep 15

      echo "Copying kubeconfig to shared location for #{cluster_name}..."
      sudo mkdir -p /vagrant/shared/#{cluster_name}
      sudo cp /etc/rancher/k3s/k3s.yaml /vagrant/shared/#{cluster_name}/kubeconfig
      sudo chmod 644 /vagrant/shared/#{cluster_name}/kubeconfig
      
      echo "K3s master for #{cluster_name} installation complete. Kubeconfig is at ./shared/#{cluster_name}/kubeconfig"
      echo "Run 'export KUBECONFIG=$(pwd)/shared/#{cluster_name}/kubeconfig' to use kubectl from your host."
    SHELL
  end

  # Fungsi untuk provisioning K3s worker
  def provision_k3s_worker(node, master_ip, worker_ip)
    node.vm.provision "shell", inline: <<-SHELL
      echo "Disabling swap..."
      sudo swapoff -a
      sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

      echo "Waiting for K3s API server on master to be ready..."
      until sudo nc -zv #{master_ip} 6443; do
        echo "K3s API server on master not yet available. Retrying in 5 seconds..."
        sleep 5
      done
      echo "K3s API server is ready."

      echo "Installing K3s worker..."
      curl -sfL https://get.k3s.io | \
        K3S_URL="https://#{master_ip}:6443" \
        K3S_TOKEN="#{$k3s_token}" \
        INSTALL_K3S_EXEC="agent --node-ip=#{worker_ip} --flannel-iface=enp0s8" \
        INSTALL_K3S_SKIP_TLS_VERIFY=true \
        sh -
    SHELL
  end

  # --- BLUE CLUSTER ---
  # Master Node Blue
  config.vm.define "blue-master" do |master|
    master_ip = "#{$blue_ip_prefix}10"
    master.vm.hostname = "blue-master"
    master.vm.network "private_network", ip: master_ip
    master.vm.network "forwarded_port", guest: 80, host: "#{$host_port_prefix_blue}80", auto_correct: true
    master.vm.network "forwarded_port", guest: 443, host: "#{$host_port_prefix_blue}43", auto_correct: true
    
    provision_k3s_master(master, master_ip, "blue")

    # Provisioning untuk mendapatkan token K3s
    master.vm.provision "shell", inline: "sudo apt-get update && sudo apt-get install -y nginx", run: "once"
    master.vm.provision "shell", inline: "sudo systemctl start nginx", run: "always"
      master.vm.provision "shell", inline: <<-SHELL
      echo "Waiting for node-token to be created..."
      while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
        sleep 2
      done
      echo "Node token found. Copying to web server..."
      sudo mkdir -p /var/www/html
      echo -n "#{$k3s_token}" | sudo tee /var/www/html/token > /dev/null
    SHELL
  end

  # Worker Nodes Blue
  (1..$num_worker_nodes).each do |i|
    config.vm.define "blue-node-#{i}" do |node|
      worker_ip = "#{$blue_ip_prefix}#{10 + i}"
      node.vm.hostname = "blue-node-#{i}"
      node.vm.network "private_network", ip: worker_ip
      provision_k3s_worker(node, "#{$blue_ip_prefix}10", worker_ip)
    end
  end

  # --- GREEN CLUSTER ---
  # Master Node Green
  config.vm.define "green-master" do |master|
    master_ip = "#{$green_ip_prefix}10"
    master.vm.hostname = "green-master"
    master.vm.network "private_network", ip: master_ip
    master.vm.network "forwarded_port", guest: 80, host: "#{$host_port_prefix_green}80", auto_correct: true
    master.vm.network "forwarded_port", guest: 443, host: "#{$host_port_prefix_green}43", auto_correct: true
    
    provision_k3s_master(master, master_ip, "green")
    
    # Provisioning untuk mendapatkan token K3s
    master.vm.provision "shell", inline: "sudo apt-get update && sudo apt-get install -y nginx", run: "once"
    master.vm.provision "shell", inline: "sudo systemctl start nginx", run: "always"
      master.vm.provision "shell", inline: <<-SHELL
      echo "Waiting for node-token to be created..."
      while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
        sleep 2
      done
      echo "Node token found. Copying to web server..."
      sudo mkdir -p /var/www/html
      echo -n "#{$k3s_token}" | sudo tee /var/www/html/token > /dev/null
    SHELL
  end

  # Worker Nodes Green
  (1..$num_worker_nodes).each do |i|
    config.vm.define "green-node-#{i}" do |node|
      worker_ip = "#{$green_ip_prefix}#{10 + i}"
      node.vm.hostname = "green-node-#{i}"
      node.vm.network "private_network", ip: worker_ip
      provision_k3s_worker(node, "#{$green_ip_prefix}10", worker_ip)
    end
  end
end