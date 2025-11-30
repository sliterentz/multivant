
#!/bin/bash
# Fix WSL to VirtualBox Host-Only Network connectivity

set -e

echo "=== WSL VirtualBox Network Fix ==="

# Check if running in WSL
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Error: This script must be run from WSL"
    exit 1
fi

# Get VirtualBox Host-Only network info from Windows
VBOX_HOSTONLY_IP=$(powershell.exe -Command "Get-NetAdapter | Where-Object {\$_.InterfaceDescription -like '*VirtualBox Host-Only*'} | Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress" | tr -d '\r')

if [ -z "$VBOX_HOSTONLY_IP" ]; then
    echo "Error: Could not find VirtualBox Host-Only adapter IP"
    exit 1
fi

echo "VirtualBox Host-Only IP: $VBOX_HOSTONLY_IP"

# Extract network prefix (e.g., 192.168.56 from 192.168.56.1)
NETWORK_PREFIX=$(echo $VBOX_HOSTONLY_IP | cut -d. -f1-3)

echo "Network prefix: $NETWORK_PREFIX"

# Check if eth1 exists in WSL
if ! ip link show eth1 &>/dev/null; then
    echo "Warning: eth1 interface not found in WSL"
    echo "Available interfaces:"
    ip link show
    exit 1
fi

# Check current eth1 configuration
echo ""
echo "Current eth1 configuration:"
ip addr show eth1

# Add route to VirtualBox Host-Only network via eth1
echo ""
echo "Adding route to $NETWORK_PREFIX.0/24 via eth1..."

# Remove existing route if present
sudo ip route del $NETWORK_PREFIX.0/24 2>/dev/null || true

# Add new route
sudo ip route add $NETWORK_PREFIX.0/24 dev eth1

echo ""
echo "Current routing table:"
ip route show

# Test connectivity
echo ""
echo "Testing connectivity to VirtualBox Host-Only network..."
if ping -c 2 -W 2 $VBOX_HOSTONLY_IP &>/dev/null; then
    echo "✓ Successfully connected to VirtualBox Host-Only adapter"
else
    echo "✗ Cannot reach VirtualBox Host-Only adapter"
    echo "  This might be normal if no VMs are running yet"
fi

# Fix SSH key permissions
echo ""
echo "Fixing SSH key permissions..."
if [ -d "$HOME/.ssh" ]; then
    chmod 700 "$HOME/.ssh"
    find "$HOME/.ssh" -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
    find "$HOME/.ssh" -type f -name "*.pub" -exec chmod 644 {} \;
    find "$HOME/.ssh" -type f -name "known_hosts*" -exec chmod 644 {} \;
    find "$HOME/.ssh" -type f -name "config" -exec chmod 600 {} \;
    echo "✓ SSH key permissions fixed"
fi

# Create or update SSH config for VMs
echo ""
echo "Configuring SSH for VirtualBox VMs..."
SSH_CONFIG="$HOME/.ssh/config"

# Backup existing config
if [ -f "$SSH_CONFIG" ]; then
    cp "$SSH_CONFIG" "$SSH_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Remove old VirtualBox VM entries
sed -i '/# VirtualBox VMs - Auto-generated/,/# End VirtualBox VMs/d' "$SSH_CONFIG" 2>/dev/null || true

# Add new configuration
cat >> "$SSH_CONFIG" <<EOF

# VirtualBox VMs - Auto-generated
Host $NETWORK_PREFIX.*
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    LogLevel ERROR
    ServerAliveInterval 60
    ServerAliveCountMax 5
    ConnectTimeout 10
    IdentitiesOnly yes

# Shared Services
Host identity-plane
    HostName $NETWORK_PREFIX.10
    User vagrant
    IdentityFile ~/.vagrant.d/insecure_private_key

Host build-plane
    HostName $NETWORK_PREFIX.20
    User vagrant
    IdentityFile ~/.vagrant.d/insecure_private_key

Host observability-plane
    HostName $NETWORK_PREFIX.30
    User vagrant
    IdentityFile ~/.vagrant.d/insecure_private_key

# End VirtualBox VMs
EOF

chmod 600 "$SSH_CONFIG"
echo "✓ SSH config updated"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Network route added: $NETWORK_PREFIX.0/24 via eth1"
echo "SSH configuration updated for VirtualBox VMs"
echo ""
echo "To test SSH connectivity to a VM, run:"
echo "  ssh vagrant@$NETWORK_PREFIX.10"
echo ""
echo "Note: This route will be lost after WSL restart."
echo "To make it persistent, add this script to your .bashrc or .profile"