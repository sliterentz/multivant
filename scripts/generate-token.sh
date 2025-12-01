#!/bin/bash

# Generate K3s Token Script

set -e

echo "════════════════════════════════════════════════════════════════"
echo "🔐 K3s Token Generator"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check if openssl is available
if ! command -v openssl &> /dev/null; then
    echo "❌ openssl is not installed"
    echo "Please install openssl first"
    exit 1
fi

# Generate token
TOKEN=$(openssl rand -hex 32)

echo "Generated K3S_TOKEN:"
echo ""
echo "  $TOKEN"
echo ""
echo "Add this to your .env file:"
echo ""
echo "  K3S_TOKEN=$TOKEN"
echo ""
echo "════════════════════════════════════════════════════════════════"