#!/bin/bash
# Automated version management setup for Ditto Cookbook
# This script automatically installs and configures correct tool versions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "=========================================="
echo "Ditto Cookbook - Automated Version Setup"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)    OS="macos";;
        Linux*)     OS="linux";;
        MINGW*|MSYS*|CYGWIN*) OS="windows";;
        *)          OS="unknown";;
    esac
    print_info "Detected OS: $OS"
}

# Check if asdf is installed
check_asdf() {
    if command -v asdf &> /dev/null; then
        print_success "asdf is already installed"
        return 0
    else
        print_warning "asdf is not installed"
        return 1
    fi
}

# Install asdf
install_asdf() {
    print_info "Installing asdf version manager..."

    case "$OS" in
        macos)
            if command -v brew &> /dev/null; then
                brew install asdf
                print_success "asdf installed via Homebrew"

                # Add to shell profile
                SHELL_NAME=$(basename "$SHELL")
                case "$SHELL_NAME" in
                    bash)
                        echo -e "\n# asdf version manager" >> ~/.bash_profile
                        echo ". $(brew --prefix asdf)/libexec/asdf.sh" >> ~/.bash_profile
                        print_info "Added asdf to ~/.bash_profile"
                        ;;
                    zsh)
                        echo -e "\n# asdf version manager" >> ~/.zshrc
                        echo ". $(brew --prefix asdf)/libexec/asdf.sh" >> ~/.zshrc
                        print_info "Added asdf to ~/.zshrc"
                        ;;
                esac
            else
                print_error "Homebrew is not installed. Please install it first: https://brew.sh"
                exit 1
            fi
            ;;
        linux)
            git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0

            # Add to shell profile
            SHELL_NAME=$(basename "$SHELL")
            case "$SHELL_NAME" in
                bash)
                    echo -e "\n# asdf version manager" >> ~/.bashrc
                    echo ". \$HOME/.asdf/asdf.sh" >> ~/.bashrc
                    print_info "Added asdf to ~/.bashrc"
                    ;;
                zsh)
                    echo -e "\n# asdf version manager" >> ~/.zshrc
                    echo ". \$HOME/.asdf/asdf.sh" >> ~/.zshrc
                    print_info "Added asdf to ~/.zshrc"
                    ;;
            esac
            print_success "asdf installed successfully"
            ;;
        windows)
            print_error "Windows detected. Please use WSL2 for development."
            print_info "Or manually install tools:"
            print_info "  - Flutter: https://docs.flutter.dev/get-started/install/windows"
            print_info "  - Node.js: https://nodejs.org/"
            exit 1
            ;;
        *)
            print_error "Unsupported OS"
            exit 1
            ;;
    esac

    # Source asdf for current session
    if [ "$OS" = "macos" ] && command -v brew &> /dev/null; then
        source "$(brew --prefix asdf)/libexec/asdf.sh"
    else
        source "$HOME/.asdf/asdf.sh"
    fi
}

# Install asdf plugins
install_asdf_plugins() {
    print_info "Installing asdf plugins..."

    # Flutter plugin
    if ! asdf plugin list | grep -q flutter; then
        asdf plugin add flutter
        print_success "Added Flutter plugin"
    else
        print_info "Flutter plugin already installed"
    fi

    # Node.js plugin
    if ! asdf plugin list | grep -q nodejs; then
        asdf plugin add nodejs
        print_success "Added Node.js plugin"
    else
        print_info "Node.js plugin already installed"
    fi

    # Python plugin
    if ! asdf plugin list | grep -q python; then
        asdf plugin add python
        print_success "Added Python plugin"
    else
        print_info "Python plugin already installed"
    fi
}

# Install tool versions from .tool-versions
install_tool_versions() {
    print_info "Installing tool versions from .tool-versions..."
    cd "$PROJECT_ROOT"

    # Install all tools
    asdf install

    print_success "All tool versions installed successfully"
}

# Verify installations
verify_versions() {
    print_info "Verifying installed versions..."
    cd "$PROJECT_ROOT"

    echo ""
    echo "Installed versions:"
    echo "-------------------"

    if command -v flutter &> /dev/null; then
        FLUTTER_VERSION=$(flutter --version 2>/dev/null | grep "Flutter" | awk '{print $2}')
        print_success "Flutter: $FLUTTER_VERSION"
    else
        print_error "Flutter not found in PATH"
    fi

    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        print_success "Node.js: $NODE_VERSION"
    else
        print_error "Node.js not found in PATH"
    fi

    if command -v python &> /dev/null; then
        PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
        print_success "Python: $PYTHON_VERSION"
    else
        print_error "Python not found in PATH"
    fi

    echo ""
}

# Setup FVM (Flutter Version Management) as alternative
setup_fvm() {
    print_info "Setting up FVM as Flutter alternative..."

    # Check if Flutter is available
    if ! command -v flutter &> /dev/null; then
        print_warning "Flutter not available, skipping FVM setup"
        return
    fi

    # Install FVM globally
    if ! command -v fvm &> /dev/null; then
        dart pub global activate fvm
        print_success "FVM installed globally"
    else
        print_info "FVM already installed"
    fi

    # Create FVM config
    FVM_CONFIG_DIR="$PROJECT_ROOT/.fvm"
    mkdir -p "$FVM_CONFIG_DIR"

    FLUTTER_VERSION=$(grep "^flutter" "$PROJECT_ROOT/.tool-versions" | awk '{print $2}')

    cat > "$FVM_CONFIG_DIR/fvm_config.json" <<EOF
{
  "flutterSdkVersion": "$FLUTTER_VERSION",
  "flavors": {}
}
EOF

    print_success "FVM config created at .fvm/fvm_config.json"

    # Update .gitignore
    if ! grep -q ".fvm/flutter_sdk" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        echo "" >> "$PROJECT_ROOT/.gitignore"
        echo "# Flutter Version Management" >> "$PROJECT_ROOT/.gitignore"
        echo ".fvm/flutter_sdk" >> "$PROJECT_ROOT/.gitignore"
        print_success "Updated .gitignore for FVM"
    fi
}

# Create .nvmrc for Node.js
create_nvmrc() {
    print_info "Creating .nvmrc for nvm users..."

    NODE_VERSION=$(grep "^nodejs" "$PROJECT_ROOT/.tool-versions" | awk '{print $2}')
    echo "$NODE_VERSION" > "$PROJECT_ROOT/.nvmrc"

    print_success "Created .nvmrc"
}

# Main execution
main() {
    detect_os
    echo ""

    # Check and install asdf
    if ! check_asdf; then
        echo ""
        read -p "asdf is not installed. Install it automatically? (y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_asdf
            echo ""
            print_success "asdf installed! Please restart your terminal and run this script again."
            echo ""
            print_info "After restarting terminal, run:"
            print_info "  cd $PROJECT_ROOT"
            print_info "  ./.claude/scripts/setup/setup-versions.sh"
            exit 0
        else
            print_error "asdf installation cancelled"
            print_info "Manual installation: https://asdf-vm.com/guide/getting-started.html"
            exit 1
        fi
    fi

    # Install plugins and tools
    echo ""
    install_asdf_plugins
    echo ""
    install_tool_versions
    echo ""
    verify_versions
    echo ""
    setup_fvm
    echo ""
    create_nvmrc

    echo ""
    echo "=========================================="
    print_success "Version setup complete!"
    echo "=========================================="
    echo ""
    print_info "All required tool versions are now installed and configured."
    echo ""
    print_info "Next steps:"
    echo "  1. Restart your terminal (or run: source ~/.zshrc)"
    echo "  2. Verify versions: flutter --version && node --version"
    echo "  3. Continue with development"
    echo ""
    print_info "The correct versions will be used automatically when in this directory."
}

# Run main function
main
