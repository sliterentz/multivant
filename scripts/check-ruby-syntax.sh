#!/bin/bash

echo "🔍 Checking Ruby syntax in all files..."
echo ""

errors_found=0

# Check Vagrantfile
echo "Checking Vagrantfile..."
if ruby -c Vagrantfile > /dev/null 2>&1; then
    echo "  ✅ Vagrantfile syntax OK"
else
    echo "  ❌ Vagrantfile has syntax errors:"
    ruby -c Vagrantfile
    errors_found=1
fi

# Check all .rb files
for file in vagrant/*.rb; do
    if [ -f "$file" ]; then
        echo "Checking $file..."
        if ruby -c "$file" > /dev/null 2>&1; then
            echo "  ✅ $file syntax OK"
        else
            echo "  ❌ $file has syntax errors:"
            ruby -c "$file"
            errors_found=1
        fi
    fi
done

echo ""
if [ $errors_found -eq 0 ]; then
    echo "✅ All Ruby files have valid syntax"
    exit 0
else
    echo "❌ Some files have syntax errors"
    exit 1
fi