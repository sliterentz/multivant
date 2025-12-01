
#!/bin/bash
# Test SSH connectivity from WSL to VirtualBox VMs

set -e

echo "=== Testing WSL to VirtualBox SSH Connectivity ==="

# Check if running in WSL
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Error: This script must be run from WSL"
    exit 1
fi

# Get VirtualBox Host-Only network info
VBOX_HOSTONLY_IP=$(powershell.exe -Command "Get-NetAdapter | Where-Object {\$_.InterfaceDescription -like '*VirtualBox Host-Only*'} | Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress" | tr -d '\r')

if [ -z "$VBOX_HOSTONLY_IP" ]; then
    echo "Error: Could not find VirtualBox Host-Only adapter IP"
    exit 1
fi

NETWORK_PREFIX=$(echo $VBOX_HOSTONLY_IP | cut -d. -f1-3)

echo "VirtualBox Host-Only Network: $NETWORK_PREFIX.0/24"
echo ""

# Function to test SSH connection
test_ssh() {
    local ip=$1
    local name=$2
    
    echo -n "Testing $name ($ip)... "
    
    if timeout 5 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR vagrant@$ip "echo 'OK'" &>/dev/null; then
        echo "✓ SUCCESS"
        return 0
    else
        echo "✗ FAILED"
        return 1
    fi
}

# Test network connectivity first
echo "1. Testing network connectivity..."
echo -n "   Pinging VirtualBox Host-Only adapter... "
if ping -c 2 -W 2 $VBOX_HOSTONLY_IP &>/dev/null; then
    echo "✓ OK"
else
    echo "✗ FAILED"
    echo ""
    echo "Network connectivity issue detected!"
    echo "Run: bash scripts/fix-wsl-vbox-network.sh"
    exit 1
fi

echo ""
echo "2. Testing SSH connectivity to VMs..."

# Get list of running VMs
RUNNING_VMS=$(powershell.exe -Command "VBoxManage list runningvms" 2>/dev/null | tr -d '\r' || echo "")

if [ -z "$RUNNING_VMS" ]; then
    echo "   No running VMs found"
    echo ""
    echo "Start VMs with: vagrant up"
    exit 0
fi

echo "   Running VMs detected"
echo ""

# Test common VM IPs
declare -A VMS=(
    ["identity-plane"]="$NETWORK_PREFIX.10"
    ["build-plane"]="$NETWORK_PREFIX.20"
    ["observability-plane"]="$NETWORK_PREFIX.30"
    ["blue-master"]="192.168.60.10"
    ["blue-node-1"]="192.168.60.11"
    ["green-master"]="192.168.70.10"
    ["green-node-1"]="192.168.70.11"
)

SUCCESS_COUNT=0
FAIL_COUNT=0

for vm_name in "${!VMS[@]}"; do
    vm_ip="${VMS[$vm_name]}"
    
    # Check if VM is in running list
    if echo "$RUNNING_VMS" | grep -q "$vm_name"; then
        if test_ssh "$vm_ip" "$vm_name"; then
            ((SUCCESS_COUNT++))
        else
            ((FAIL_COUNT++))
        fi
    fi
done

echo ""
echo "=== Test Summary ==="
echo "Successful connections: $SUCCESS_COUNT"
echo "Failed connections: $FAIL_COUNT"

if [ $FAIL_COUNT -gt 0 ]; then
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Ensure VMs are fully booted: vagrant status"
    echo "2. Check VM network configuration: vagrant ssh <vm-name> -c 'ip addr'"
    echo "3. Verify SSH service is running: vagrant ssh <vm-name> -c 'systemctl status ssh'"
    echo "4. Re-run network fix: bash scripts/fix-wsl-vbox-network.sh"
    exit 1
fi

echo ""
echo "✓ All SSH connections successful!"