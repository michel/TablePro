# Git Commands for Auto-Reconnect Feature

## Quick Commit (Excluding Documentation)

```bash
# Stage only the modified Swift files
git add SSHTunnelManager.swift DatabaseManager.swift PostgreSQLDriver.swift

# Commit with detailed message
git commit -F COMMIT_MESSAGE.txt

# Push to remote
git push
```

---

## Alternative: One-Line Commands

```bash
# All in one
git add SSHTunnelManager.swift DatabaseManager.swift PostgreSQLDriver.swift && \
git commit -F COMMIT_MESSAGE.txt && \
git push
```

---

## Files to Commit (Modified Code)

✅ **SSHTunnelManager.swift**
   - Added health monitoring system
   - Added tunnel death detection
   - Added notification system
   - ~60 lines added

✅ **DatabaseManager.swift**
   - Added SSH tunnel death handler
   - Added automatic reconnection logic
   - Added notification observer
   - ~35 lines added

✅ **PostgreSQLDriver.swift**
   - Added connection error detection
   - Added auto-reconnect logic
   - Added reconnect helper methods
   - ~85 lines added

---

## Files to EXCLUDE (Documentation)

❌ **AUTO_RECONNECT_GUIDE.md** - Full documentation
❌ **AUTO_RECONNECT_QUICK_REF.md** - Quick reference
❌ **COMMIT_MESSAGE.txt** - Commit message template
❌ **commit_push.sh** - Helper script
❌ **GIT_COMMANDS.md** - This file

---

## Optional: Commit Documentation Separately

If you want to add documentation later:

```bash
# Add documentation files
git add AUTO_RECONNECT_GUIDE.md AUTO_RECONNECT_QUICK_REF.md

# Commit documentation
git commit -m "docs: Add comprehensive auto-reconnect documentation

- Add detailed implementation guide (AUTO_RECONNECT_GUIDE.md)
- Add quick reference card (AUTO_RECONNECT_QUICK_REF.md)
- Include testing procedures, configuration options, and FAQ
- Document all auto-reconnect features and limitations"

# Push
git push
```

---

## Verify Before Committing

```bash
# Check which files are modified
git status

# Preview changes in each file
git diff SSHTunnelManager.swift
git diff DatabaseManager.swift
git diff PostgreSQLDriver.swift

# Check what will be committed
git diff --cached --name-only

# See detailed stats
git diff --cached --stat
```

---

## If You Need to Undo

```bash
# Unstage files (before commit)
git reset SSHTunnelManager.swift DatabaseManager.swift PostgreSQLDriver.swift

# Undo last commit (after commit, before push)
git reset --soft HEAD~1

# Undo commit and unstage (after commit, before push)
git reset HEAD~1

# Revert pushed commit (after push) - creates new commit
git revert HEAD
```

---

## Using the Helper Script

```bash
# Make script executable
chmod +x commit_push.sh

# Run interactive commit script
./commit_push.sh
```

The script will:
1. ✅ Stage only the 3 modified Swift files
2. 📋 Show you what's being committed
3. 🤔 Ask for confirmation
4. 📝 Commit with detailed message
5. 🚀 Ask to push to remote
6. ✅ Complete the process

---

## Git Log After Commit

Your commit will appear as:

```
commit abc123def456...
Author: Your Name <your.email@example.com>
Date:   Wed Feb 4 2026 ...

    feat: Add comprehensive auto-reconnect for SSH tunnels and database connections
    
    Implements automatic reconnection handling for network interruptions, VPN
    disconnections, and database connection failures across all supported
    database types.
    
    ### SSH Tunnel Auto-Reconnect
    - Add health monitoring system that checks tunnel status every 30 seconds
    ...
```

---

## Summary

**Files to commit:**
- SSHTunnelManager.swift
- DatabaseManager.swift  
- PostgreSQLDriver.swift

**Command:**
```bash
git add SSHTunnelManager.swift DatabaseManager.swift PostgreSQLDriver.swift
git commit -F COMMIT_MESSAGE.txt
git push
```

**Or use the script:**
```bash
chmod +x commit_push.sh && ./commit_push.sh
```

Done! 🎉
