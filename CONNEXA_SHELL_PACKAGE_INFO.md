# Connexa-Shell Package - File Manifest

## Overview

This package contains all files needed to create the standalone `Connexa-Shell` repository.

## Package Contents

### 1. connexa-shell-installer.sh (16 KB)
**Purpose**: Main standalone installation script

**What it does:**
- Applies backend fix (load_dotenv)
- Applies frontend fix (double /api)
- Creates automatic backups
- Restarts services
- Comprehensive verification

**Key Features:**
- Self-contained (no external dependencies)
- Idempotent (safe to run multiple times)
- Colored output for easy reading
- Security hardened defaults
- Creates missing files if needed

**Usage:**
```bash
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-shell-installer.sh | sudo bash
```

### 2. CONNEXA_SHELL_README.md → README.md (9.2 KB)
**Purpose**: Complete documentation for the repository

**Sections:**
- Quick installation guide
- Feature overview
- Configuration instructions
- Security recommendations
- Troubleshooting guide
- Integration examples
- Technical details

**Rename to:** `README.md` when copying to new repository

### 3. CONNEXA_SHELL_GITIGNORE → .gitignore (450 bytes)
**Purpose**: Git ignore rules for the repository

**Excludes:**
- Backup files
- Environment files (.env)
- Logs
- Temporary files
- Python/Node artifacts
- IDE files

**Rename to:** `.gitignore` when copying to new repository

### 4. SETUP_CONNEXA_SHELL_REPO.md (6.9 KB)
**Purpose**: Step-by-step guide for creating the new repository

**Contents:**
- Repository creation steps
- File copying instructions
- Git initialization commands
- Post-setup tasks
- Testing procedures
- Maintenance guidelines

**Note**: This is a guide document, not included in the final repository

## Files Mapping

When creating the Connexa-Shell repository, rename files as follows:

| Source File (FIX-CONNEXXA) | Destination (Connexa-Shell) |
|---------------------------|----------------------------|
| `connexa-shell-installer.sh` | `connexa-shell-installer.sh` |
| `CONNEXA_SHELL_README.md` | `README.md` |
| `CONNEXA_SHELL_GITIGNORE` | `.gitignore` |

## Setup Commands

```bash
# Step 1: Create new repository on GitHub
# Repository name: Connexa-Shell
# Do NOT initialize with README

# Step 2: Prepare files
mkdir -p /tmp/connexa-shell
cd /tmp/connexa-shell

# Step 3: Copy files from FIX-CONNEXXA
cp /home/runner/work/FIX-CONNEXXA/FIX-CONNEXXA/connexa-shell-installer.sh .
cp /home/runner/work/FIX-CONNEXXA/FIX-CONNEXXA/CONNEXA_SHELL_README.md README.md
cp /home/runner/work/FIX-CONNEXXA/FIX-CONNEXXA/CONNEXA_SHELL_GITIGNORE .gitignore

# Step 4: Initialize git
git init
git branch -M main
chmod +x connexa-shell-installer.sh

# Step 5: Commit
git add .
git commit -m "Initial commit: CONNEXA Shell Installer v1.0.0"

# Step 6: Push
git remote add origin https://github.com/mrolivershea-cyber/Connexa-Shell.git
git push -u origin main
```

## Repository Structure

Final structure in Connexa-Shell repository:

```
Connexa-Shell/
├── README.md                     # Documentation (from CONNEXA_SHELL_README.md)
├── connexa-shell-installer.sh    # Installer script (executable)
├── .gitignore                    # Git ignore (from CONNEXA_SHELL_GITIGNORE)
└── LICENSE                       # (Optional) Add your license
```

## Version Information

- **Version**: 1.0.0
- **Release Date**: 2024-11-01
- **Script Lines**: ~450
- **Total Package Size**: ~32 KB
- **Dependencies**: None (self-contained)

## Testing

After creating the repository, test the installer:

```bash
# Test URL accessibility
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-shell-installer.sh | head -20

# Run on test system
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-shell-installer.sh | sudo bash
```

## Features Summary

### Backend Fix
- Adds `from dotenv import load_dotenv` after line 17 in server.py
- Adds `load_dotenv()` call
- Creates complete server.py if missing

### Frontend Fix
- Fixes: `const API = ${BACKEND_URL}/api;`
- To: `const API = BACKEND_URL.endsWith("/api") ? BACKEND_URL : ${BACKEND_URL}/api;`
- Prevents double /api paths

### Additional Features
- ✅ Automatic timestamped backups
- ✅ Idempotent design
- ✅ Security hardened (CORS, host binding)
- ✅ Comprehensive verification
- ✅ Service restart
- ✅ Colored output
- ✅ Error handling

## Integration

The standalone installer can be used:

1. **Direct installation**: One-line curl command
2. **Docker**: Add to Dockerfile
3. **Ansible**: Use in playbooks
4. **Terraform**: Include in provisioning
5. **CI/CD**: Integrate in pipelines
6. **Manual**: Download and execute

## Maintenance

When updating the installer:

1. Edit `connexa-shell-installer.sh`
2. Update VERSION variable in script
3. Commit changes
4. Create new git tag
5. Create GitHub release

## Support

- **Repository**: https://github.com/mrolivershea-cyber/Connexa-Shell
- **Documentation**: https://github.com/mrolivershea-cyber/FIX-CONNEXXA
- **Issues**: https://github.com/mrolivershea-cyber/Connexa-Shell/issues

## Related Files in FIX-CONNEXXA

These files remain in the FIX-CONNEXXA repository for reference:

- `MINIFIX_PATCH.sh` - Original development version
- `MINIFIX_README.md` - Detailed technical documentation
- `USAGE_EXAMPLES.md` - 16 usage examples
- `QUICKSTART.md` - Quick reference
- `SECURITY_SUMMARY.md` - Security guidelines
- `IMPLEMENTATION_SUMMARY.md` - Implementation details

## Quick Reference

**Install command:**
```bash
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-shell-installer.sh | sudo bash
```

**Repository URL:**
```
https://github.com/mrolivershea-cyber/Connexa-Shell
```

**Documentation:**
- README.md in the repository
- Full docs at FIX-CONNEXXA repository

**Version:** v1.0.0
**Status:** Ready for deployment
**License:** Same as main CONNEXA project

---

**Prepared by**: @copilot
**Date**: 2024-11-01
**For**: @mrolivershea-cyber
