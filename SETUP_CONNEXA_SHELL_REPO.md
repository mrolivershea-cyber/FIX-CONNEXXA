# Setup Guide: Connexa-Shell Repository

This guide walks you through setting up the standalone `Connexa-Shell` repository.

## Quick Setup

### Step 1: Create the Repository

1. Go to GitHub: https://github.com/new
2. Repository name: `Connexa-Shell`
3. Description: `Standalone Shell installer for CONNEXA application fixes`
4. Visibility: Public (or Private as needed)
5. **Do NOT** initialize with README (we'll add our own)
6. Click "Create repository"

### Step 2: Prepare the Files

The following files are ready in the `FIX-CONNEXXA` repository:

```
FIX-CONNEXXA/
├── connexa-shell-installer.sh     # Main installer script
├── CONNEXA_SHELL_README.md        # README for the new repo
└── CONNEXA_SHELL_GITIGNORE        # .gitignore for the new repo
```

### Step 3: Initialize and Push

```bash
# Create a temporary directory for the new repo
mkdir -p /tmp/connexa-shell
cd /tmp/connexa-shell

# Initialize git
git init
git branch -M main

# Copy files from FIX-CONNEXXA
cp /home/runner/work/FIX-CONNEXXA/FIX-CONNEXXA/connexa-shell-installer.sh .
cp /home/runner/work/FIX-CONNEXXA/FIX-CONNEXXA/CONNEXA_SHELL_README.md README.md
cp /home/runner/work/FIX-CONNEXXA/FIX-CONNEXXA/CONNEXA_SHELL_GITIGNORE .gitignore

# Make installer executable
chmod +x connexa-shell-installer.sh

# Add files
git add connexa-shell-installer.sh README.md .gitignore

# Commit
git commit -m "Initial commit: CONNEXA Shell Installer v1.0.0

- Add standalone Shell installer script
- Add comprehensive README documentation
- Add .gitignore for repository

Features:
- Backend fix: load_dotenv() support
- Frontend fix: double /api path correction
- Automatic backups
- Service restart
- Security hardening
- Idempotent design"

# Add remote (replace with your actual repository URL)
git remote add origin https://github.com/mrolivershea-cyber/Connexa-Shell.git

# Push to GitHub
git push -u origin main
```

## Alternative: Using GitHub CLI

If you have GitHub CLI installed:

```bash
# Create the repository
gh repo create mrolivershea-cyber/Connexa-Shell --public --description "Standalone Shell installer for CONNEXA application fixes"

# Clone it
cd /tmp
gh repo clone mrolivershea-cyber/Connexa-Shell
cd Connexa-Shell

# Copy files
cp /home/runner/work/FIX-CONNEXXA/FIX-CONNEXXA/connexa-shell-installer.sh .
cp /home/runner/work/FIX-CONNEXXA/FIX-CONNEXXA/CONNEXA_SHELL_README.md README.md
cp /home/runner/work/FIX-CONNEXXA/FIX-CONNEXXA/CONNEXA_SHELL_GITIGNORE .gitignore

# Make executable
chmod +x connexa-shell-installer.sh

# Commit and push
git add .
git commit -m "Initial commit: CONNEXA Shell Installer v1.0.0"
git push origin main
```

## Repository Structure

After setup, your repository will look like:

```
Connexa-Shell/
├── README.md                     # Comprehensive documentation
├── connexa-shell-installer.sh    # Main installer script (executable)
├── .gitignore                    # Git ignore rules
└── LICENSE                       # (Optional) Add a license file
```

## Post-Setup Tasks

### 1. Add Topics/Tags

On GitHub, add relevant topics to help people find your repository:
- `shell`
- `bash`
- `installer`
- `connexa`
- `devops`
- `automation`

### 2. Update Repository Description

Set a clear description:
```
Standalone Shell installer for CONNEXA application fixes - adds .env support and fixes API path issues
```

### 3. Create a Release

```bash
# Tag the version
git tag -a v1.0.0 -m "Release v1.0.0: Initial standalone installer"
git push origin v1.0.0

# Or use GitHub CLI
gh release create v1.0.0 --title "v1.0.0: Initial Release" --notes "First release of standalone CONNEXA Shell installer"
```

### 4. Enable GitHub Pages (Optional)

For documentation hosting:
1. Go to Settings → Pages
2. Source: Deploy from branch
3. Branch: main / (root)
4. Save

### 5. Add Repository Badges

Add to the top of README.md:

```markdown
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](https://github.com/mrolivershea-cyber/Connexa-Shell/releases)
[![Shell](https://img.shields.io/badge/shell-bash-blue.svg)](https://www.gnu.org/software/bash/)
```

## Testing the Installation

After pushing to GitHub, test the one-line installer:

```bash
# Test the installer URL
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-shell-installer.sh | head -20

# On a test system, run the full install
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-shell-installer.sh | sudo bash
```

## Updating FIX-CONNEXXA Repository

After creating the Connexa-Shell repository, update the main FIX-CONNEXXA README to reference it:

```markdown
## Related Repositories

- **Connexa-Shell**: [Standalone installer](https://github.com/mrolivershea-cyber/Connexa-Shell) - Ready-to-use Shell installer
- **FIX-CONNEXXA**: Complete documentation and additional scripts (this repository)
```

## Maintenance

### Updating the Installer

When you make changes to the installer:

```bash
cd /path/to/Connexa-Shell

# Edit the file
nano connexa-shell-installer.sh

# Update version number in the script
# VERSION="1.0.1"

# Commit changes
git add connexa-shell-installer.sh
git commit -m "Update to v1.0.1: Fix XYZ issue"

# Tag the new version
git tag -a v1.0.1 -m "Release v1.0.1"

# Push
git push origin main
git push origin v1.0.1
```

### Creating Releases

For each version:
1. Update VERSION in script
2. Commit changes
3. Create git tag
4. Create GitHub release with changelog

## File Descriptions

### connexa-shell-installer.sh
- **Purpose**: Main installation script
- **Size**: ~16KB
- **Lines**: ~450
- **Features**: Colored output, backups, verification, idempotent

### README.md
- **Purpose**: Complete documentation
- **Sections**: Installation, configuration, troubleshooting, examples
- **Size**: ~9KB

### .gitignore
- **Purpose**: Exclude unnecessary files
- **Includes**: Backups, logs, env files, temp files

## Verification Checklist

After setup, verify:

- [ ] Repository is created on GitHub
- [ ] All files are pushed to main branch
- [ ] connexa-shell-installer.sh is executable (755 permissions)
- [ ] README.md displays correctly on GitHub
- [ ] One-line install URL works
- [ ] Repository has description and topics
- [ ] (Optional) Release v1.0.0 is created
- [ ] (Optional) GitHub Pages is enabled

## Support

If you encounter issues:

1. Check file permissions: `ls -la`
2. Verify git remote: `git remote -v`
3. Check GitHub repository settings
4. Ensure you have push access to the repository

## Summary

The Connexa-Shell repository provides:
- ✅ Standalone, self-contained installer
- ✅ No dependencies on other repositories
- ✅ Easy one-line installation
- ✅ Comprehensive documentation
- ✅ Ready for distribution

Users can now install CONNEXA fixes with a single command without needing to clone or navigate the main FIX-CONNEXXA repository.
