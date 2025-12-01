#!/bin/bash
# File: /home/ripjim/pando_box/multivant/scripts/generate-inventory.sh

set -e

# Load environment variables
source .env 2>/dev/null || true

# Default values
NUM_WORKER_NODES=${NUM_WORKER_NODES:-1}
BLUE_IP_PREFIX=${BLUE_IP_PREFIX:-192.168.56.}
GREEN_IP_PREFIX=${GREEN_IP_PREFIX:-192.168.57.}
SHARED_SERVICES_IP_PREFIX=${SHARED_SERVICES_IP_PREFIX:-192.168.58.}
ENABLE_IDENTITY_PLANE=${ENABLE_IDENTITY_PLANE:-false}
ENABLE_BUILD_PLANE=${ENABLE_BUILD_PLANE:-false}

INVENTORY_FILE="ansible/inventory/hosts.ini"

echo "Generating Ansible inventory..."

cat > "$INVENTORY_FILE" << EOF
# Auto-generated inventory file
# Generated at: $(date)

[blue_master]
blue-master ansible_host=${BLUE_IP_PREFIX}10

[blue_workers]
EOF

# Add blue workers
for i in $(seq 1 $NUM_WORKER_NODES); do
    echo "blue-node-$i ansible_host=${BLUE_IP_PREFIX}$((10 + i))" >> "$INVENTORY_FILE"
done

cat >> "$INVENTORY_FILE" << EOF

[green_master]
green-master ansible_host=${GREEN_IP_PREFIX}10

[green_workers]
EOF

# Add green workers
for i in $(seq 1 $NUM_WORKER_NODES); do
    echo "green-node-$i ansible_host=${GREEN_IP_PREFIX}$((10 + i))" >> "$INVENTORY_FILE"
done

cat >> "$INVENTORY_FILE" << EOF

[identity_plane]
EOF

if [ "$ENABLE_IDENTITY_PLANE" = "true" ]; then
    echo "identity-plane ansible_host=${SHARED_SERVICES_IP_PREFIX}10" >> "$INVENTORY_FILE"
else
    echo "# identity-plane ansible_host=${SHARED_SERVICES_IP_PREFIX}10" >> "$INVENTORY_FILE"
fi

cat >> "$INVENTORY_FILE" << EOF

[build_plane]
EOF

if [ "$ENABLE_BUILD_PLANE" = "true" ]; then
    echo "build-plane ansible_host=${SHARED_SERVICES_IP_PREFIX}20" >> "$INVENTORY_FILE"
else
    echo "# build-plane ansible_host=${SHARED_SERVICES_IP_PREFIX}20" >> "$INVENTORY_FILE"
fi

cat >> "$INVENTORY_FILE" << EOF

[blue_cluster:children]
blue_master
blue_workers

[green_cluster:children]
green_master
green_workers

[masters:children]
blue_master
green_master

[workers:children]
blue_workers
green_workers

[all:vars]
ansible_user=vagrant
ansible_ssh_private_key_file=~/.vagrant.d/insecure_private_key
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

echo "✅ Inventory file generated: $INVENTORY_FILE"
cat "$INVENTORY_FILE"