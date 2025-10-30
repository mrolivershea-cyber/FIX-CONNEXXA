#!/bin/bash

################################################################################
# CONNEXA v7.4.8 - Universal Download and Install Script
################################################################################
# This script handles downloading and installing the patch with fallback options
# Works even when git is not available or when direct downloads fail
################################################################################

set -e

GITHUB_REPO="mrolivershea-cyber/FIX-CONNEXXA"
BRANCH="copilot/fix-pptp-tunnel-issues"
VERSION="v7.4.8"

echo "=================================="
echo "CONNEXA ${VERSION} Patch Installer"
echo "=================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo "ℹ️  $1"
}

# Check if we're root
if [ "$EUID" -ne 0 ]; then 
    print_warning "This script should be run as root for full functionality"
    print_info "Some operations may require sudo"
fi

# Detect download tool
DOWNLOAD_TOOL=""
if command -v wget &> /dev/null; then
    DOWNLOAD_TOOL="wget"
    print_success "Found wget"
elif command -v curl &> /dev/null; then
    DOWNLOAD_TOOL="curl"
    print_success "Found curl"
else
    print_error "Neither wget nor curl found!"
    print_info "Please install wget or curl:"
    echo "  Ubuntu/Debian: apt-get install wget"
    echo "  CentOS/RHEL: yum install wget"
    exit 1
fi

# Function to download file
download_file() {
    local url=$1
    local output=$2
    
    print_info "Downloading: $output"
    
    if [ "$DOWNLOAD_TOOL" = "wget" ]; then
        wget -q --show-progress -O "$output" "$url" || return 1
    else
        curl -fsSL -o "$output" "$url" || return 1
    fi
    
    return 0
}

# Create temporary directory
TEMP_DIR=$(mktemp -d)
print_info "Created temporary directory: $TEMP_DIR"

cd "$TEMP_DIR"

# Base URL for raw files
BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}"

print_info "Downloading installation script..."

# Try to download the main installation script
if download_file "${BASE_URL}/install_connexa_v7_4_8_patch.sh" "install_connexa_v7_4_8_patch.sh"; then
    print_success "Downloaded install_connexa_v7_4_8_patch.sh"
    chmod +x install_connexa_v7_4_8_patch.sh
else
    print_error "Failed to download installation script"
    print_info "Trying alternative method..."
    
    # Fallback: try to clone the repository
    if command -v git &> /dev/null; then
        print_info "Attempting to clone repository..."
        git clone -b "${BRANCH}" "https://github.com/${GITHUB_REPO}.git" connexa
        cd connexa
        
        if [ -f "install_connexa_v7_4_8_patch.sh" ]; then
            print_success "Repository cloned successfully"
            chmod +x install_connexa_v7_4_8_patch.sh
        else
            print_error "Installation script not found in repository"
            exit 1
        fi
    else
        print_error "git not available for fallback method"
        print_info "Please install git or ensure network access to GitHub"
        exit 1
    fi
fi

# Display file information
print_info "Installation script details:"
ls -lh install_connexa_v7_4_8_patch.sh

echo ""
print_success "Download complete!"
echo ""
print_info "Ready to install CONNEXA ${VERSION} patch"
echo ""

# Ask user if they want to proceed
read -p "Do you want to run the installation now? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Starting installation..."
    echo ""
    bash ./install_connexa_v7_4_8_patch.sh
else
    print_info "Installation script saved in: $TEMP_DIR"
    print_info "To install later, run:"
    echo "  cd $TEMP_DIR"
    echo "  bash ./install_connexa_v7_4_8_patch.sh"
fi

print_success "Script completed"
