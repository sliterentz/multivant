#!/bin/bash

echo "🔧 Fixing deprecated Ruby File.exists? method..."

# Find all Ruby files and Vagrantfile
find . -type f \( -name "*.rb" -o -name "Vagrantfile" \) -exec sed -i 's/File\.exists?/File.exist?/g' {} \;

echo "✅ All Ruby files fixed"

# Verify changes
echo ""
echo "Checking for remaining File.exists? usage:"
grep -r "File\.exists?" . --include="*.rb" --include="Vagrantfile" || echo "✅ No File.exists? found"