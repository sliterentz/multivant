module InventoryGenerator
  class << self
    def generate_inventory
      inventory = {
        'all' => {
          'children' => {
            'k3s_cluster' => {
              'children' => {
                'k3s_master' => {
                  'hosts' => {}
                },
                'k3s_worker' => {
                  'hosts' => {}
                }
              }
            },
            'blue_cluster' => {
              'children' => {
                'control_plane' => {
                  'hosts' => {}
                },
                'data_plane' => {
                  'hosts' => {}
                }
              }
            },
            'green_cluster' => {
              'children' => {
                'control_plane' => {
                  'hosts' => {}
                },
                'data_plane' => {
                  'hosts' => {}
                }
              }
            },
            'shared_services' => {
              'hosts' => {}
            }
          }
        }
      }

      # Add blue cluster nodes
      inventory['all']['children']['blue_cluster']['children']['control_plane']['hosts']['blue-master'] = {
        'ansible_host' => "#{VagrantConfig.blue_ip_prefix}10"
      }
      inventory['all']['children']['k3s_cluster']['children']['k3s_master']['hosts']['blue-master'] = {
        'ansible_host' => "#{VagrantConfig.blue_ip_prefix}10"
      }

      (1..VagrantConfig.num_worker_nodes).each do |i|
        node_name = "blue-node-#{i}"
        inventory['all']['children']['blue_cluster']['children']['data_plane']['hosts'][node_name] = {
          'ansible_host' => "#{VagrantConfig.blue_ip_prefix}#{10 + i}"
        }
        inventory['all']['children']['k3s_cluster']['children']['k3s_worker']['hosts'][node_name] = {
          'ansible_host' => "#{VagrantConfig.blue_ip_prefix}#{10 + i}"
        }
      end

      # Add green cluster nodes
      inventory['all']['children']['green_cluster']['children']['control_plane']['hosts']['green-master'] = {
        'ansible_host' => "#{VagrantConfig.green_ip_prefix}10"
      }
      inventory['all']['children']['k3s_cluster']['children']['k3s_master']['hosts']['green-master'] = {
        'ansible_host' => "#{VagrantConfig.green_ip_prefix}10"
      }

      (1..VagrantConfig.num_worker_nodes).each do |i|
        node_name = "green-node-#{i}"
        inventory['all']['children']['green_cluster']['children']['data_plane']['hosts'][node_name] = {
          'ansible_host' => "#{VagrantConfig.green_ip_prefix}#{10 + i}"
        }
        inventory['all']['children']['k3s_cluster']['children']['k3s_worker']['hosts'][node_name] = {
          'ansible_host' => "#{VagrantConfig.green_ip_prefix}#{10 + i}"
        }
      end

      # Add shared services
      if VagrantConfig.enable_identity_plane?
        inventory['all']['children']['shared_services']['hosts']['identity-plane'] = {
          'ansible_host' => "#{VagrantConfig.shared_services_ip_prefix}10"
        }
      end

      if VagrantConfig.enable_build_plane?
        inventory['all']['children']['shared_services']['hosts']['build-plane'] = {
          'ansible_host' => "#{VagrantConfig.shared_services_ip_prefix}20"
        }
      end

      if VagrantConfig.enable_observability?
        inventory['all']['children']['shared_services']['hosts']['observability-plane'] = {
          'ansible_host' => "#{VagrantConfig.shared_services_ip_prefix}30"
        }
      end

      inventory
    end

    def save_inventory(path = 'ansible/inventory/vagrant.yml')
      require 'yaml'
      require 'fileutils'

      inventory = generate_inventory
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, inventory.to_yaml)
      
      puts "✅ Inventory file generated: #{path}"
    end
  end
end