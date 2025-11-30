#!/bin/bash

# Create directory structure for modular Vagrantfile
echo "📁 Creating directory structure..."

# Create vagrant directory
mkdir -p vagrant

# Create ansible inventory directory
mkdir -p ansible/inventory

# Create shared directory
mkdir -p shared

echo "✅ Directory structure created successfully"
echo ""
echo "Directory structure:"
echo "├── vagrant/"
echo "│   ├── config.rb"
echo "│   ├── helpers.rb"
echo "│   ├── provisioners.rb"
echo "│   └── inventory_generator.rb"
echo "├── ansible/"
echo "│   └── inventory/"
echo "│       └── vagrant.yml (auto-generated)"
echo "└── shared/"