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
  config.vm.network :forwarded_port, guest: 22, host: 2522, auto_correct: true, id: "ssh"
  # Gunakan box Ubuntu 22.04 LTS (Jammy Jellyfish)
  config.vm.box = "ubuntu/jammy64"
  
  # Sinkronisasi folder script ke semua node
  config.vm.synced_folder "./scripts", "/vagrant_scripts", disabled: true

  # Atasi masalah sinkronisasi folder saat menggunakan WSL
  if ENV['WSL_DISTRO_NAME']
    config.vm.synced_folder ".", "/vagrant", type: "rsync"
    # config.vm.synced_folder "./scripts", "/vagrant_scripts", type: "rsync"
  end

  # Pengaturan default untuk provider VirtualBox
  config.vm.provider "virtualbox" do |vb|
    vb.memory = $vm_memory
    vb.cpus = $vm_cpus
    # Fix for VBoxManage error: "RawFile#0 failed to create the raw output file /dev/null"
    vb.customize ["modifyvm", :id, "--uartmode1", "disconnected"]
  end

  # Pengaturan default untuk provider Hyper-V
  config.vm.provider "hyperv" do |hv|
    hv.memory = $vm_memory
    hv.cpus = $vm_cpus
    hv.vm_config_path = ".vagrant/hyperv_config"
    hv.check_admin_acls = false
    hv.linked_clone = true
    hv.ip_address_timeout = 120
    hv.network_switch_name = "WSL-HyperV-NAT"
  end

  # --- BLUE CLUSTER ---
  # Master Node Blue
  config.vm.define "blue-master" do |master|
    master_ip = "#{$blue_ip_prefix}10"
    master.vm.hostname = "blue-master"
    master.vm.network "private_network", ip: master_ip
    master.vm.network "forwarded_port", guest: 80, host: "#{$host_port_prefix_blue}80", auto_correct: true
    master.vm.network "forwarded_port", guest: 443, host: "#{$host_port_prefix_blue}43", auto_correct: true

    master.vm.provision "ansible" do |ansible|
      ansible.playbook = "ansible/playbook.yml"
      ansible.groups = {
        "masters" => ["blue-master"],
        "blue_cluster" => ["blue-master"]
      }
      ansible.extra_vars = {
        k3s_token: $k3s_token,
        cluster_name: "blue",
        master_ip: "#{$blue_ip_prefix}10"
      }
    end
  end

  # Worker Nodes Blue
  (1..$num_worker_nodes).each do |i|
    config.vm.define "blue-node-#{i}" do |node|
      worker_ip = "#{$blue_ip_prefix}#{10 + i}"
      node.vm.hostname = "blue-node-#{i}"
      node.vm.network "private_network", ip: worker_ip
      # provision_k3s_worker(node, "#{$blue_ip_prefix}10", worker_ip)

      node.vm.provision "ansible" do |ansible|
        ansible.playbook = "ansible/playbook.yml"
        ansible.groups = {
          "workers" => ["blue-node-#{i}"],
          "blue_cluster" => ["blue-node-#{i}"]
        }
        ansible.extra_vars = {
          k3s_token: $k3s_token,
          master_ip: "#{$blue_ip_prefix}10",
          worker_ip: "#{$blue_ip_prefix}#{10 + i}"
        }
      end
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
    master.vm.provision "ansible" do |ansible|
      ansible.playbook = "ansible/playbook.yml"
      ansible.groups = {
        "masters" => ["green-master"],
        "green_cluster" => ["green-master"]
      }
      ansible.extra_vars = {
        k3s_token: $k3s_token,
        cluster_name: "green",
        master_ip: "#{$green_ip_prefix}10"
      }
    end    
  end

  # Worker Nodes Green
  (1..$num_worker_nodes).each do |i|
    config.vm.define "green-node-#{i}" do |node|
      worker_ip = "#{$green_ip_prefix}#{10 + i}"
      node.vm.hostname = "green-node-#{i}"
      node.vm.network "private_network", ip: worker_ip
      # provision_k3s_worker(node, "#{$green_ip_prefix}10", worker_ip)

      node.vm.provision "ansible" do |ansible|
        ansible.playbook = "ansible/playbook.yml"
        ansible.groups = {
          "workers" => ["green-node-#{i}"],
          "green_cluster" => ["green-node-#{i}"]
        }
        ansible.extra_vars = {
          k3s_token: $k3s_token,
          master_ip: "#{$green_ip_prefix}10",
          worker_ip: "#{$green_ip_prefix}#{10 + i}"
        }
      end  
    end
  end
end