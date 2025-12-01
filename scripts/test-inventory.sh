#!/bin/bash

set -e

cd "$(dirname "$0")/../ansible"

echo "=========================================="
echo "Testing Ansible Dynamic Inventory"
echo "=========================================="

# Make inventory script executable
chmod +x inventory.py

echo ""
echo "1. Testing inventory list..."
./inventory.py --list | jq '.'

echo ""
echo "2. Testing Ansible inventory..."
ansible-inventory --list -i inventory.py | jq '.'

echo ""
echo "3. Testing Ansible ping to all hosts..."
ansible all -i inventory.py -m ping

echo ""
echo "=========================================="
echo "✅ Inventory test completed"
echo "=========================================="