# -*- Multicluster Blue Green Deployment With Vagrant -*-
# Production-Ready Configuration with Platform Lifecycle Planes

# Load environment variables
unless Vagrant.has_plugin?("vagrant-env")
  abort "The 'vagrant-env' vagrant plugin is not installed. Please run: vagrant plugin install vagrant-env"
end
require 'vagrant-env'

# Load helper modules
require_relative 'vagrant/config'
require_relative 'vagrant/helpers'
require_relative 'vagrant/provisioners'

# ============================================================================
# VAGRANT CONFIGURATION
# ============================================================================

Vagrant.configure("2") do |config|
  # Base Configuration
  VagrantConfig.configure_base(config)
  VagrantConfig.print_configuration
  
  # Global SSH Configuration for all nodes
  config.ssh.insert_key = true
  config.ssh.forward_agent = true
  config.ssh.keep_alive = true
  config.ssh.connect_timeout = 300
  config.ssh.shell = "bash -c 'BASH_ENV=/etc/profile exec bash'"
  
  # ============================================================================
  # SHARED SERVICES (Platform Lifecycle Planes)
  # ============================================================================
  
  # Identity Plane
  if VagrantConfig.enable_identity_plane?
    config.vm.define "identity-plane", primary: false do |node|
      VagrantHelpers.configure_shared_service_node(
        node,
        name: "identity-plane",
        ip: "#{VagrantConfig.shared_services_ip_prefix}10",
        memory: VagrantConfig.identity_plane_memory,
        cpus: VagrantConfig.identity_plane_cpus,
        ports: {
          "Keycloak" => [8080, 8080],
          "Vault" => [8200, 8200]
        },
        node_type: "identity-plane"
      )
      VagrantConfig.configure_ssh_access(node, "#{VagrantConfig.shared_services_ip_prefix}10")
    end
  end

  # Build Plane
  if VagrantConfig.enable_build_plane?
    config.vm.define "build-plane", primary: false do |node|
      VagrantHelpers.configure_shared_service_node(
        node,
        name: "build-plane",
        ip: "#{VagrantConfig.shared_services_ip_prefix}20",
        memory: VagrantConfig.build_plane_memory,
        cpus: VagrantConfig.build_plane_cpus,
        ports: {
          "Jenkins" => [8081, 8081],
          "Harbor" => [5000, 5000],
          "GitLab" => [8082, 8082],
          "ArgoCD" => [8083, 8083]
        },
        node_type: "build-plane",
        extra_vars: {
          blue_master_ip: "#{VagrantConfig.blue_ip_prefix}10",
          green_master_ip: "#{VagrantConfig.green_ip_prefix}10"
        }
      )
      # Configure SSH access for WSL
      VagrantConfig.configure_ssh_access(node, "#{VagrantConfig.shared_services_ip_prefix}20")
    end
  end

  # Observability Plane
  if VagrantConfig.enable_observability?
    config.vm.define "observability-plane", primary: false do |node|
      VagrantHelpers.configure_shared_service_node(
        node,
        name: "observability-plane",
        ip: "#{VagrantConfig.shared_services_ip_prefix}30",
        memory: VagrantConfig.observability_memory,
        cpus: VagrantConfig.observability_cpus,
        ports: {
          "Prometheus" => [9090, 9090],
          "Grafana" => [3000, 3000],
          "Loki" => [3100, 3100],
          "Jaeger" => [16686, 16686],
          "AlertManager" => [9093, 9093]
        },
        node_type: "observability-plane",
        extra_vars: {
          blue_master_ip: "#{VagrantConfig.blue_ip_prefix}10",
          green_master_ip: "#{VagrantConfig.green_ip_prefix}10"
        }
      )
      # Configure SSH access for WSL
      VagrantConfig.configure_ssh_access(node, "#{VagrantConfig.shared_services_ip_prefix}30")
    end
  end

  # ============================================================================
  # BLUE CLUSTER
  # ============================================================================
  
  # Blue Master Node
  config.vm.define "blue-master", primary: true do |node|
    VagrantHelpers.configure_k3s_master_node(
      node,
      cluster_name: "blue",
      hostname: "blue-master",
      ip: "#{VagrantConfig.blue_ip_prefix}10",
      memory: VagrantConfig.control_plane_memory,
      cpus: VagrantConfig.control_plane_cpus,
      port_prefix: VagrantConfig.host_port_prefix_blue
    )
    # Configure SSH access for WSL
    VagrantConfig.configure_ssh_access(node, "#{VagrantConfig.blue_ip_prefix}10")
  end

  # Blue Worker Nodes
  (1..VagrantConfig.num_worker_nodes).each do |i|
    config.vm.define "blue-node-#{i}", autostart: true do |node|
      VagrantHelpers.configure_k3s_worker_node(
        node,
        cluster_name: "blue",
        hostname: "blue-node-#{i}",
        worker_number: i,
        ip: "#{VagrantConfig.blue_ip_prefix}#{10 + i}",
        master_ip: "#{VagrantConfig.blue_ip_prefix}10",
        memory: VagrantConfig.data_plane_memory,
        cpus: VagrantConfig.data_plane_cpus,
        port_prefix: VagrantConfig.host_port_prefix_blue
      )
      # Configure SSH access for WSL
      VagrantConfig.configure_ssh_access(node, "#{VagrantConfig.blue_ip_prefix}#{10 + i}")
    end
  end

  # ============================================================================
  # GREEN CLUSTER
  # ============================================================================
  
  # Green Master Node
  config.vm.define "green-master", primary: true do |node|
    VagrantHelpers.configure_k3s_master_node(
      node,
      cluster_name: "green",
      hostname: "green-master",
      ip: "#{VagrantConfig.green_ip_prefix}10",
      memory: VagrantConfig.control_plane_memory,
      cpus: VagrantConfig.control_plane_cpus,
      port_prefix: VagrantConfig.host_port_prefix_green
    )
    # Configure SSH access for WSL
    VagrantConfig.configure_ssh_access(node, "#{VagrantConfig.green_ip_prefix}10")
  end

  # Green Worker Nodes
  (1..VagrantConfig.num_worker_nodes).each do |i|
    config.vm.define "green-node-#{i}", autostart: true do |node|
      VagrantHelpers.configure_k3s_worker_node(
        node,
        cluster_name: "green",
        hostname: "green-node-#{i}",
        worker_number: i,
        ip: "#{VagrantConfig.green_ip_prefix}#{10 + i}",
        master_ip: "#{VagrantConfig.green_ip_prefix}10",
        memory: VagrantConfig.data_plane_memory,
        cpus: VagrantConfig.data_plane_cpus,
        port_prefix: VagrantConfig.host_port_prefix_green
      )
      # Configure SSH access for WSL
      VagrantConfig.configure_ssh_access(node, "#{VagrantConfig.green_ip_prefix}#{10 + i}")
    end
  end
end