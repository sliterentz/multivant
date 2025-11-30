#!/bin/bash

# Cleanup Script

set -e

echo "════════════════════════════════════════════════════════════════"
echo "🧹 Multivant Cleanup"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Confirm cleanup
read -p "This will destroy all VMs and clean up files. Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo "🗑️  Destroying all VMs..."
vagrant destroy -f

echo "🗑️  Cleaning up Vagrant files..."
rm -rf .vagrant

echo "🗑️  Cleaning up Ansible files..."
rm -rf ansible/*.retry
rm -rf ansible/inventory/vagrant.yml

echo "🗑️  Cleaning up kubeconfig files..."
rm -f kubeconfig-blue.yaml
rm -f kubeconfig-green.yaml

echo "🗑️  Cleaning up shared folder..."
rm -rf shared/*

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Cleanup completed!"
echo "════════════════════════════════════════════════════════════════"