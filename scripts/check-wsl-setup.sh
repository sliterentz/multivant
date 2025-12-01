#!/bin/bash

# WSL Setup Checker Script

set -e

echo "════════════════════════════════════════════════════════════════"
echo "🔍 WSL Environment Checker"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check if running in WSL
if ! grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
    echo "❌ Not running in WSL environment"
    exit 1
fi

echo "✅ Running in WSL"
echo ""

# WSL Version
echo "📋 WSL Information:"
if command -v wsl.exe &> /dev/null; then
    WSL_VERSION=$(wsl.exe -l -v 2>/dev/null | grep -i "$(hostname)" | awk '{print $3}' | tr -d '\r')
    echo "  Version: WSL $WSL_VERSION"
fi

DISTRO_NAME=$(grep -oP '(?<=^NAME=).+' /etc/os-release | tr -d '"')
DISTRO_VERSION=$(grep -oP '(?<=^VERSION=).+' /etc/os-release | tr -d '"')
echo "  Distribution: $DISTRO_NAME $DISTRO_VERSION"
echo ""

# Check systemd
echo "🔧 System Configuration:"
if ps -p 1 -o comm= | grep -q systemd; then
    echo "  ✅ systemd: Enabled"
else
    echo "  ⚠️  systemd: Disabled"
    echo "     Enable in /etc/wsl.conf:"
    echo "     [boot]"
    echo "     systemd=true"
fi
echo ""

# Check .wslconfig
echo "📝 WSL Configuration:"
if [ -n "$USERPROFILE" ]; then
    WSLCONFIG_PATH=$(wslpath "$USERPROFILE")/.wslconfig
    
    if [ -f "$WSLCONFIG_PATH" ]; then
        echo "  ✅ .wslconfig found"
        echo ""
        echo "  Current settings:"
        cat "$WSLCONFIG_PATH" | sed 's/^/    /'
    else
        echo "  ⚠️  .wslconfig not found"
        echo ""
        echo "  Create at: $USERPROFILE\\.wslconfig"
        echo ""
        echo "  Recommended content:"
        echo "    [wsl2]"
        echo "    memory=16GB"
        echo "    processors=4"
        echo "    swap=8GB"
        echo "    localhostForwarding=true"
    fi
else
    echo "  ⚠️  Cannot determine Windows user profile"
fi
echo ""

# Check VirtualBox
echo "🖥️  VirtualBox Status:"
if command -v VBoxManage.exe &> /dev/null; then
    VBOX_VERSION=$(VBoxManage.exe --version 2>/dev/null | tr -d '\r')
    echo "  ✅ VirtualBox accessible: $VBOX_VERSION"
    
    # Check if VirtualBox service is running
    VBOX_SERVICE_STATUS=$(powershell.exe -Command "Get-Service -Name 'VBoxSDS' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status" 2>/dev/null | tr -d '\r')
    if [ -n "$VBOX_SERVICE_STATUS" ]; then
        if [ "$VBOX_SERVICE_STATUS" = "Running" ]; then
            echo "  ✅ VirtualBox Service: $VBOX_SERVICE_STATUS"
        else
            echo "  ⚠️  VirtualBox Service: $VBOX_SERVICE_STATUS"
            echo "     Start VirtualBox on Windows to enable the service"
        fi
    fi
    
    # List running VMs
    echo ""
    echo "  Running VMs:"
    RUNNING_VMS=$(VBoxManage.exe list runningvms 2>/dev/null | tr -d '\r')
    if [ -z "$RUNNING_VMS" ]; then
        echo "    None"
    else
        echo "$RUNNING_VMS" | sed 's/^/    /'
    fi
else
    echo "  ❌ VirtualBox not accessible from WSL"
    echo "     Check if VirtualBox is installed on Windows"
    echo "     Path should be: C:\\Program Files\\Oracle\\VirtualBox"
    echo ""
    echo "  To add VirtualBox to PATH, add this to ~/.bashrc:"
    echo "    export PATH=\"\$PATH:/mnt/c/Program Files/Oracle/VirtualBox\""
fi
echo ""

# Check Vagrant
echo "🔧 Vagrant Status:"
if command -v vagrant &> /dev/null; then
    VAGRANT_VERSION=$(vagrant --version)
    echo "  ✅ Vagrant: $VAGRANT_VERSION"
    
    # Check Vagrant plugins
    echo ""
    echo "  Installed plugins:"
    vagrant plugin list | sed 's/^/    /'
    
    # Check Vagrant home
    if [ -n "$VAGRANT_HOME" ]; then
        echo ""
        echo "  VAGRANT_HOME: $VAGRANT_HOME"
    fi
else
    echo "  ❌ Vagrant not installed"
fi
echo ""

# Check network connectivity
echo "🌐 Network Connectivity:"
if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
    echo "  ✅ Internet: Connected"
else
    echo "  ❌ Internet: Not connected"
fi

# Check Windows host connectivity
if [ -n "$WSL_DISTRO_NAME" ]; then
    WIN_HOST_IP=$(ip route show | grep -i default | awk '{ print $3}')
    if [ -n "$WIN_HOST_IP" ]; then
        echo "  Windows Host IP: $WIN_HOST_IP"
        if ping -c 1 -W 2 "$WIN_HOST_IP" &> /dev/null; then
            echo "  ✅ Windows Host: Reachable"
        else
            echo "  ⚠️  Windows Host: Not reachable"
        fi
    fi
fi
echo ""

# Check memory and CPU
echo "💻 System Resources:"
TOTAL_MEM=$(free -h | awk '/^Mem:/ {print $2}')
AVAILABLE_MEM=$(free -h | awk '/^Mem:/ {print $7}')
CPU_CORES=$(nproc)

echo "  Total Memory: $TOTAL_MEM"
echo "  Available Memory: $AVAILABLE_MEM"
echo "  CPU Cores: $CPU_CORES"
echo ""

# Check disk space
echo "💾 Disk Space:"
df -h / | tail -1 | awk '{printf "  Root: %s / %s (%s used)\n", $3, $2, $5}'

if [ -d "/mnt/c" ]; then
    df -h /mnt/c | tail -1 | awk '{printf "  C: Drive: %s / %s (%s used)\n", $3, $2, $5}'
fi
echo ""

# Check required packages
echo "📦 Required Packages:"
PACKAGES=("curl" "wget" "git" "make" "openssl")
for pkg in "${PACKAGES[@]}"; do
    if command -v "$pkg" &> /dev/null; then
        echo "  ✅ $pkg: Installed"
    else
        echo "  ❌ $pkg: Not installed"
    fi
done
echo ""

# Check project directory
echo "📁 Project Directory:"
if [ -f "Vagrantfile" ]; then
    echo "  ✅ Vagrantfile found"
else
    echo "  ⚠️  Vagrantfile not found in current directory"
fi

if [ -f ".env" ]; then
    echo "  ✅ .env file found"
    
    # Check K3S_TOKEN
    if grep -q "K3S_TOKEN=your-secure-token-here" .env 2>/dev/null; then
        echo "  ⚠️  K3S_TOKEN not configured in .env"
    else
        echo "  ✅ K3S_TOKEN configured"
    fi
else
    echo "  ⚠️  .env file not found"
fi

if [ -d "shared" ]; then
    echo "  ✅ shared directory exists"
else
    echo "  ⚠️  shared directory not found"
fi
echo ""

# Network mode check
echo "🔌 Network Mode:"
if [ -n "$USERPROFILE" ]; then
    WSLCONFIG_PATH=$(wslpath "$USERPROFILE")/.wslconfig
    if [ -f "$WSLCONFIG_PATH" ]; then
        if grep -q "networkingMode=mirrored" "$WSLCONFIG_PATH" 2>/dev/null; then
            echo "  ✅ Mirrored networking mode enabled"
        else
            echo "  ℹ️  NAT networking mode (default)"
        fi
    else
        echo "  ℹ️  NAT networking mode (default)"
    fi
fi
echo ""

# Recommendations
echo "════════════════════════════════════════════════════════════════"
echo "💡 Recommendations"
echo "════════════════════════════════════════════════════════════════"

ISSUES_FOUND=false

# Check systemd
if ! ps -p 1 -o comm= | grep -q systemd; then
    echo "⚠️  Enable systemd for better compatibility"
    echo "   Add to /etc/wsl.conf:"
    echo "   [boot]"
    echo "   systemd=true"
    echo ""
    ISSUES_FOUND=true
fi

# Check VirtualBox
if ! command -v VBoxManage.exe &> /dev/null; then
    echo "⚠️  VirtualBox not accessible from WSL"
    echo "   Install VirtualBox on Windows or add to PATH"
    echo ""
    ISSUES_FOUND=true
fi

# Check .wslconfig
if [ -n "$USERPROFILE" ]; then
    WSLCONFIG_PATH=$(wslpath "$USERPROFILE")/.wslconfig
    if [ ! -f "$WSLCONFIG_PATH" ]; then
        echo "⚠️  Create .wslconfig for better performance"
        echo "   Location: $USERPROFILE\\.wslconfig"
        echo ""
        ISSUES_FOUND=true
    fi
fi

# Check memory
AVAILABLE_MEM_MB=$(free -m | awk '/^Mem:/ {print $7}')
if [ "$AVAILABLE_MEM_MB" -lt 8192 ]; then
    echo "⚠️  Low available memory (< 8GB)"
    echo "   Consider increasing WSL memory allocation in .wslconfig"
    echo ""
    ISSUES_FOUND=true
fi

# Check .env
if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found"
    echo "   Run: make init"
    echo ""
    ISSUES_FOUND=true
elif grep -q "K3S_TOKEN=your-secure-token-here" .env 2>/dev/null; then
    echo "⚠️  K3S_TOKEN not configured"
    echo "   Run: bash scripts/generate-token.sh"
    echo ""
    ISSUES_FOUND=true
fi

if [ "$ISSUES_FOUND" = false ]; then
    echo "✅ No issues found! Your WSL environment is ready."
    echo ""
    echo "Next steps:"
    echo "  1. Run: make up"
    echo "  2. Check status: make status"
    echo "  3. View cluster info: make info"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"