#!/bin/bash

# Git commit and push script for auto-reconnect feature
# Excludes documentation markdown files

echo "🔍 Staging modified files (excluding .md documentation)..."

# Add the modified Swift files
git add SSHTunnelManager.swift
git add DatabaseManager.swift
git add PostgreSQLDriver.swift

# Verify what's staged
echo ""
echo "📋 Files staged for commit:"
git diff --cached --name-only

echo ""
echo "📊 Summary of changes:"
git diff --cached --stat

echo ""
read -p "🤔 Proceed with commit? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Commit with the prepared message
    echo "📝 Committing changes..."
    git commit -F COMMIT_MESSAGE.txt
    
    echo ""
    read -p "🚀 Push to remote? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "⬆️  Pushing to remote..."
        git push
        echo "✅ Done!"
    else
        echo "⏸️  Commit created but not pushed. Run 'git push' when ready."
    fi
else
    echo "❌ Commit cancelled. Changes are still staged."
    echo "   Run 'git reset' to unstage."
fi

echo ""
echo "📚 Note: Documentation files were excluded:"
echo "   - AUTO_RECONNECT_GUIDE.md"
echo "   - AUTO_RECONNECT_QUICK_REF.md"
echo "   - COMMIT_MESSAGE.txt"
echo ""
echo "   Add them separately if needed:"
echo "   git add AUTO_RECONNECT_*.md"
echo "   git commit -m 'docs: Add auto-reconnect documentation'"
