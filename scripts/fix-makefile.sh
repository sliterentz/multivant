#!/bin/bash

# Fix Makefile indentation (convert spaces to tabs)

MAKEFILE="Makefile"

if [ ! -f "$MAKEFILE" ]; then
    echo "❌ Makefile not found"
    exit 1
fi

echo "🔧 Fixing Makefile indentation..."

# Backup original
cp "$MAKEFILE" "${MAKEFILE}.backup"

# Convert leading spaces to tabs (only for command lines)
# Lines that should have tabs are those that start with spaces followed by commands
sed -i 's/^    /\t/' "$MAKEFILE"

echo "✅ Makefile fixed"
echo "📝 Backup saved as ${MAKEFILE}.backup"