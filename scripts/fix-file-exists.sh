#!/bin/bash

echo "🔧 Fixing File.exists? to File.exist? in all Ruby files..."
echo ""

# Find and fix in all Ruby files
find . -type f \( -name "*.rb" -o -name "Vagrantfile" \) | while read -r file; do
    if grep -q "File\.exists?" "$file"; then
        echo "Fixing: $file"
        sed -i 's/File\.exists?/File.exist?/g' "$file"
        echo "  ✅ Fixed"
    fi
done

echo ""
echo "Checking for remaining File.exists? usage..."
remaining=$(grep -r "File\.exists?" . --include="*.rb" --include="Vagrantfile" 2>/dev/null)

if [ -z "$remaining" ]; then
    echo "✅ All File.exists? have been replaced with File.exist?"
else
    echo "⚠️  Still found File.exists? in:"
    echo "$remaining"
fi