#!/bin/bash

# Setup Environment Script

set -e

echo "════════════════════════════════════════════════════════════════"
echo "🚀 Multivant Environment Setup"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Detect if running in WSL
IS_WSL=false
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
    IS_WSL=true
    echo "🐧 Detected WSL environment"
fi

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check Vagrant
if ! command -v vagrant &> /dev/null; then
    echo "❌ Vagrant is not installed"
    if [ "$IS_WSL" = true ]; then
        echo "Please install Vagrant in WSL from: https://www.vagrantup.com/downloads"
    else
        echo "Please install Vagrant from: https://www.vagrantup.com/downloads"
    fi
    exit 1
fi
echo "✅ Vagrant: $(vagrant --version)"

# Check VirtualBox
echo "🔍 Checking VirtualBox..."
if [ "$IS_WSL" = true ]; then
    # Check VirtualBox on Windows host from WSL
    if command -v VBoxManage.exe &> /dev/null; then
        VBOX_VERSION=$(VBoxManage.exe --version 2>/dev/null | tr -d '\r')
        echo "✅ VirtualBox (Windows): $VBOX_VERSION"
    else
        # Try alternative path
        WIN_VBOX_PATH="/mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"
        if [ -f "$WIN_VBOX_PATH" ]; then
            VBOX_VERSION=$("$WIN_VBOX_PATH" --version 2>/dev/null | tr -d '\r')
            echo "✅ VirtualBox (Windows): $VBOX_VERSION"
            
            # Add to PATH if not already there
            if ! command -v VBoxManage.exe &> /dev/null; then
                echo "⚠️  Adding VirtualBox to PATH..."
                export PATH="$PATH:/mnt/c/Program Files/Oracle/VirtualBox"
                echo 'export PATH="$PATH:/mnt/c/Program Files/Oracle/VirtualBox"' >> ~/.bashrc
                echo "✅ VirtualBox added to PATH (restart shell to persist)"
            fi
        else
            echo "❌ VirtualBox is not installed on Windows host"
            echo ""
            echo "Please install VirtualBox on Windows from:"
            echo "  https://www.virtualbox.org/wiki/Downloads"
            echo ""
            echo "After installation, VBoxManage.exe should be accessible from WSL"
            echo "Default location: C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe"
            exit 1
        fi
    fi
else
    # Check VirtualBox on native Linux
    if ! command -v VBoxManage &> /dev/null; then
        echo "❌ VirtualBox is not installed"
        echo "Please install VirtualBox from: https://www.virtualbox.org/wiki/Downloads"
        exit 1
    fi
    echo "✅ VirtualBox: $(VBoxManage --version)"
fi

# Check dotenv plugin
if ! vagrant plugin list | grep -q dotenv; then
    echo "⚠️  dotenv plugin not found"
    echo "Installing dotenv plugin..."
    vagrant plugin install dotenv
    echo "✅ dotenv plugin installed"
else
    echo "✅ dotenv plugin is installed"
fi

echo ""
echo "📁 Setting up directories..."

# Create directories
mkdir -p shared
mkdir -p scripts
mkdir -p ansible/inventory
mkdir -p vagrant

echo "✅ Directories created"

echo ""
echo "📝 Setting up configuration files..."

# Check if .env exists
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        echo "✅ .env file created from .env.example"
        echo ""
        echo "⚠️  IMPORTANT: Please edit .env file and set K3S_TOKEN"
        echo "   Generate token with: bash scripts/generate-token.sh"
    else
        echo "❌ .env.example not found"
        exit 1
    fi
else
    echo "✅ .env file already exists"
fi

# Check K3S_TOKEN
if grep -q "K3S_TOKEN=your-secure-token-here" .env 2>/dev/null; then
    echo ""
    echo "⚠️  WARNING: K3S_TOKEN is not set in .env file"
    echo "   Generate token with: bash scripts/generate-token.sh"
fi

# WSL-specific checks and recommendations
if [ "$IS_WSL" = true ]; then
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "📝 WSL-Specific Recommendations"
    echo "════════════════════════════════════════════════════════════════"
    
    # Check .wslconfig
    WSLCONFIG="$USERPROFILE/.wslconfig"
    if [ -n "$USERPROFILE" ]; then
        WSLCONFIG_PATH=$(wslpath "$USERPROFILE")/.wslconfig
        
        if [ ! -f "$WSLCONFIG_PATH" ]; then
            echo "⚠️  .wslconfig not found"
            echo ""
            echo "For better performance, create .wslconfig in Windows user directory:"
            echo "  Location: $USERPROFILE\\.wslconfig"
            echo ""
            echo "Recommended content:"
            echo "  [wsl2]"
            echo "  memory=16GB"
            echo "  processors=4"
            echo "  swap=8GB"
            echo "  localhostForwarding=true"
            echo ""
        else
            echo "✅ .wslconfig found at: $WSLCONFIG_PATH"
        fi
    fi
    
    # Check if running with systemd
    if ! ps -p 1 -o comm= | grep -q systemd; then
        echo ""
        echo "⚠️  systemd is not enabled in WSL"
        echo ""
        echo "To enable systemd, add to /etc/wsl.conf:"
        echo "  [boot]"
        echo "  systemd=true"
        echo ""
        echo "Then restart WSL: wsl --shutdown"
    else
        echo "✅ systemd is enabled"
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Environment setup completed!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Edit .env file and set K3S_TOKEN"
echo "     Generate with: bash scripts/generate-token.sh"
echo "  2. Review and adjust resource allocation in .env"
echo "  3. Start the environment: make up"
echo ""

if [ "$IS_WSL" = true ]; then
    echo "WSL Tips:"
    echo "  - Ensure VirtualBox is running on Windows"
    echo "  - Use 'make' commands for easier management"
    echo "  - Check 'make info' for cluster endpoints"
    echo ""
fi