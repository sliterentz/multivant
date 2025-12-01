#!/bin/bash

set -e

CLUSTER_NAME=${1:-blue}
MASTER_IP="192.168.56.10"

echo "=========================================="
echo "Network Diagnostics for ${CLUSTER_NAME} cluster"
echo "=========================================="

echo ""
echo "1. Testing basic connectivity..."
if ping -c 3 -W 2 $MASTER_IP > /dev/null 2>&1; then
    echo "✅ Ping successful to $MASTER_IP"
else
    echo "❌ Ping failed to $MASTER_IP"
    echo "   This indicates a network routing issue between WSL and VirtualBox"
fi

echo ""
echo "2. Testing port 6443 connectivity..."
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$MASTER_IP/6443" 2>/dev/null; then
    echo "✅ Port 6443 is reachable"
else
    echo "❌ Port 6443 is NOT reachable"
    echo "   K3s API server might not be running or firewall is blocking"
fi

echo ""
echo "3. Testing TLS handshake with openssl..."
if timeout 10 openssl s_client -connect $MASTER_IP:6443 -showcerts < /dev/null 2>/dev/null | grep -q "Verify return code"; then
    echo "✅ TLS handshake successful"
else
    echo "❌ TLS handshake failed"
    echo "   This is the root cause of kubectl timeout"
fi

echo ""
echo "4. Checking routing table..."
ip route | grep $MASTER_IP || echo "No specific route to $MASTER_IP"

echo ""
echo "5. Checking if VM is running..."
vagrant status $CLUSTER_NAME-master | grep -q "running" && echo "✅ VM is running" || echo "❌ VM is not running"

echo ""
echo "6. Testing from inside VM..."
vagrant ssh $CLUSTER_NAME-master -c "sudo systemctl status k3s | head -n 5" 2>/dev/null || echo "❌ Cannot connect to VM"

echo ""
echo "=========================================="
echo "Recommendations:"
echo "=========================================="
echo "If TLS handshake fails:"
echo "1. Try accessing kubectl from inside the VM"
echo "2. Use kubectl with --insecure-skip-tls-verify flag"
echo "3. Configure K3s to use HTTP instead of HTTPS (not recommended for production)"
echo "4. Check Windows Firewall settings"
echo "5. Restart WSL: wsl --shutdown (from PowerShell)"