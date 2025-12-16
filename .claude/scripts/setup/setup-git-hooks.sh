#!/bin/bash

# Git Hooks Setup Script
# Sets up Git hooks for maintaining code quality across developers

set -e

echo ""
echo "🔧 Setting up Git Hooks for Quality Maintenance"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the root directory of the git repository
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

if [[ -z "$GIT_ROOT" ]]; then
    echo -e "${RED}✗${NC} Not a git repository"
    echo "Please run this script from within a git repository"
    exit 1
fi

HOOKS_DIR="$GIT_ROOT/.git/hooks"
SCRIPTS_DIR="$GIT_ROOT/.claude/scripts"

# Ensure hooks directory exists
if [[ ! -d "$HOOKS_DIR" ]]; then
    echo -e "${RED}✗${NC} Git hooks directory not found: $HOOKS_DIR"
    exit 1
fi

echo ""
echo -e "${BLUE}Installing Git hooks...${NC}"
echo ""

# ============================================
# 1. Pre-Commit Hook
# ============================================
echo -e "${BLUE}[1/3]${NC} Installing pre-commit hook..."

cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/bash

# Pre-Commit Hook
# Runs security and language checks before allowing commit

set -e

echo ""
echo "🔒 Running Pre-Commit Quality Checks..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FAILED=0

# Get the root directory
GIT_ROOT=$(git rev-parse --show-toplevel)
SCRIPTS_DIR="$GIT_ROOT/.claude/scripts"
SETUP_FILE="$GIT_ROOT/.claude/settings.local.json"

# ============================================
# Setup Status Check (Non-blocking warning)
# ============================================
if [[ -f "$SETUP_FILE" ]]; then
    # Function to safely extract JSON values
    get_json_value() {
        local file=$1
        local key=$2
        grep -o "\"$key\"[[:space:]]*:[[:space:]]*[^,}]*" "$file" | sed 's/.*:[[:space:]]*//;s/"//g;s/[[:space:]]*$//' | head -1
    }

    SETUP_COMPLETED=$(get_json_value "$SETUP_FILE" "completed")
    CLAUDE_INSTALLED=$(get_json_value "$SETUP_FILE" "installed")
    MCP_CONFIGURED=$(get_json_value "$SETUP_FILE" "configured")

    # Show friendly recommendations (non-blocking)
    if [[ "$SETUP_COMPLETED" != "true" ]]; then
        echo ""
        echo -e "${YELLOW}ℹ${NC}  Tip: Complete your development environment setup for the best experience"
        echo -e "${YELLOW}→${NC} Run: ./.claude/scripts/setup/complete-setup.sh"
        echo ""
    fi

    if [[ "$CLAUDE_INSTALLED" == "false" ]]; then
        echo -e "${YELLOW}ℹ${NC}  Tip: Claude Code provides enhanced development experience"
        echo -e "${YELLOW}→${NC} Install from: https://claude.com/claude-code"
        echo ""
    fi

    if [[ "$CLAUDE_INSTALLED" == "true" && "$MCP_CONFIGURED" == "false" ]]; then
        echo -e "${YELLOW}ℹ${NC}  Tip: MCP servers enhance Claude Code capabilities"
        echo -e "${YELLOW}→${NC} Run: ./.claude/scripts/setup/setup-mcp-servers.sh"
        echo ""
    fi
else
    # First-time user - friendly welcome message
    echo ""
    echo -e "${BLUE}👋 Welcome! This appears to be your first commit.${NC}"
    echo ""
    echo -e "${YELLOW}ℹ${NC}  For the best development experience, complete the setup:"
    echo -e "${YELLOW}→${NC} Run: ./.claude/scripts/setup/complete-setup.sh"
    echo ""
fi

# ============================================
# Version Check (Non-blocking)
# ============================================
if [[ -f "$SCRIPTS_DIR/checks/version-check.sh" ]]; then
    echo -e "${BLUE}[0/2]${NC} Checking tool versions..."
    "$SCRIPTS_DIR/checks/version-check.sh" || true  # Always succeeds, just shows warnings/fixes
    echo ""
fi

# Check if scripts exist
if [[ ! -f "$SCRIPTS_DIR/checks/security-check.sh" ]]; then
    echo -e "${YELLOW}⚠${NC}  Security check script not found, skipping..."
else
    echo -e "${BLUE}[1/2]${NC} Running security checks..."
    if ! "$SCRIPTS_DIR/checks/security-check.sh"; then
        echo -e "${RED}✗${NC} Security check failed!"
        FAILED=1
    else
        echo -e "${GREEN}✓${NC} Security check passed"
    fi
fi

if [[ ! -f "$SCRIPTS_DIR/checks/language-check.sh" ]]; then
    echo -e "${YELLOW}⚠${NC}  Language check script not found, skipping..."
else
    echo -e "${BLUE}[2/2]${NC} Running language checks..."
    if ! "$SCRIPTS_DIR/checks/language-check.sh"; then
        echo -e "${RED}✗${NC} Language check failed!"
        FAILED=1
    else
        echo -e "${GREEN}✓${NC} Language check passed"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAILED -eq 1 ]]; then
    echo -e "${RED}❌ Pre-commit checks failed!${NC}"
    echo ""
    echo "Please fix the issues above before committing."
    echo ""
    echo -e "${BLUE}💡 Need help?${NC} Ask Claude Code how to resolve these issues:"
    echo "   • Open Claude Code and describe the error message"
    echo "   • Claude Code can help you fix security or language violations"
    echo ""
    echo "To bypass this check (not recommended), use: git commit --no-verify"
    echo ""
    exit 1
else
    echo -e "${GREEN}✅ Pre-commit checks passed!${NC}"
    echo ""
fi

exit 0
EOF

chmod +x "$HOOKS_DIR/pre-commit"
echo -e "${GREEN}✓${NC} Pre-commit hook installed"

# ============================================
# 2. Commit-Msg Hook
# ============================================
echo -e "${BLUE}[2/3]${NC} Installing commit-msg hook..."

cat > "$HOOKS_DIR/commit-msg" << 'EOF'
#!/bin/bash

# Commit-Msg Hook
# Validates commit message format and content

set -e

COMMIT_MSG_FILE=$1
COMMIT_MSG=$(cat "$COMMIT_MSG_FILE")

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Skip checks for merge commits
if grep -q "^Merge" "$COMMIT_MSG_FILE"; then
    exit 0
fi

# Skip checks for revert commits
if grep -q "^Revert" "$COMMIT_MSG_FILE"; then
    exit 0
fi

FAILED=0

# Check 1: First line length (subject line should be under 72 characters)
FIRST_LINE=$(echo "$COMMIT_MSG" | head -n1)
if [[ ${#FIRST_LINE} -gt 72 ]]; then
    echo -e "${YELLOW}⚠${NC}  Commit message subject line is long (${#FIRST_LINE} chars, recommended max 72)"
    echo "    Consider making it more concise"
fi

# Check 2: English only (check for Japanese and other non-ASCII characters)
# Check if the message contains any bytes outside the ASCII range (0x00-0x7F)
# Using perl if available, otherwise use a simpler check
if command -v perl &> /dev/null; then
    if echo "$COMMIT_MSG" | perl -ne 'exit 1 if /[^\x00-\x7F]/'; then
        :  # ASCII only, pass
    else
        echo -e "${RED}✗${NC} Commit message contains non-English characters"
        echo "    Project policy requires English-only commit messages"
        FAILED=1
    fi
else
    # Fallback: check for common non-ASCII byte patterns
    if printf "%s" "$COMMIT_MSG" | LC_ALL=C grep -q '[^ -~]'; then
        echo -e "${RED}✗${NC} Commit message contains non-English characters"
        echo "    Project policy requires English-only commit messages"
        FAILED=1
    fi
fi

# Check 3: Professional language (very basic check)
if echo "$COMMIT_MSG" | grep -qiE '\b(fuck|shit|damn|crap|wtf|stupid|dumb)\b'; then
    echo -e "${RED}✗${NC} Commit message contains inappropriate language"
    echo "    Please use professional language in commit messages"
    FAILED=1
fi

if [[ $FAILED -eq 1 ]]; then
    echo ""
    echo -e "${RED}❌ Commit message validation failed!${NC}"
    echo ""
    echo "Current message:"
    echo "---"
    echo "$COMMIT_MSG"
    echo "---"
    echo ""
    echo "Please revise your commit message."
    echo ""
    echo -e "${BLUE}💡 Need help?${NC} Ask Claude Code for commit message suggestions:"
    echo "   • Describe your changes to Claude Code"
    echo "   • Claude Code can help you write a proper commit message"
    echo ""
    echo "To bypass this check (not recommended), use: git commit --no-verify"
    echo ""
    exit 1
fi

exit 0
EOF

chmod +x "$HOOKS_DIR/commit-msg"
echo -e "${GREEN}✓${NC} Commit-msg hook installed"

# ============================================
# 3. Pre-Push Hook
# ============================================
echo -e "${BLUE}[3/3]${NC} Installing pre-push hook..."

cat > "$HOOKS_DIR/pre-push" << 'EOF'
#!/bin/bash

# Pre-Push Hook
# Runs comprehensive checks before pushing to remote

set -e

echo ""
echo "🚀 Running Pre-Push Quality Checks..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FAILED=0

# Get the root directory
GIT_ROOT=$(git rev-parse --show-toplevel)
SCRIPTS_DIR="$GIT_ROOT/.claude/scripts"

# Check 0: Version Check (Non-blocking)
if [[ -f "$SCRIPTS_DIR/checks/version-check.sh" ]]; then
    echo -e "${BLUE}[0/4]${NC} Checking tool versions..."
    "$SCRIPTS_DIR/checks/version-check.sh" || true  # Always succeeds, just shows warnings/fixes
    echo ""
fi

# Check 1: Security
if [[ -f "$SCRIPTS_DIR/checks/security-check.sh" ]]; then
    echo -e "${BLUE}[1/4]${NC} Running security checks..."
    if ! "$SCRIPTS_DIR/checks/security-check.sh"; then
        echo -e "${RED}✗${NC} Security check failed!"
        FAILED=1
    else
        echo -e "${GREEN}✓${NC} Security check passed"
    fi
else
    echo -e "${YELLOW}⚠${NC}  Security check script not found, skipping..."
fi

# Check 2: Language
if [[ -f "$SCRIPTS_DIR/checks/language-check.sh" ]]; then
    echo -e "${BLUE}[2/4]${NC} Running language checks..."
    if ! "$SCRIPTS_DIR/checks/language-check.sh"; then
        echo -e "${RED}✗${NC} Language check failed!"
        FAILED=1
    else
        echo -e "${GREEN}✓${NC} Language check passed"
    fi
else
    echo -e "${YELLOW}⚠${NC}  Language check script not found, skipping..."
fi

# Check 3: Dart Analysis (if applicable)
echo -e "${BLUE}[3/4]${NC} Running code analysis..."
if command -v dart &> /dev/null; then
    if [[ -f "$GIT_ROOT/pubspec.yaml" ]]; then
        if ! dart analyze --fatal-infos 2>&1 | grep -q "No issues found"; then
            echo -e "${RED}✗${NC} Dart analysis found issues"
            echo ""
            dart analyze --fatal-infos 2>&1 | head -20
            echo ""
            FAILED=1
        else
            echo -e "${GREEN}✓${NC} Dart analysis passed"
        fi
    else
        echo -e "${YELLOW}⚠${NC}  No pubspec.yaml found, skipping Dart checks"
    fi
else
    echo -e "${YELLOW}⚠${NC}  Dart not installed, skipping Dart checks"
fi

# Check 4: Architecture Documentation
echo -e "${BLUE}[4/4]${NC} Checking architecture documentation..."
if [[ -f "$SCRIPTS_DIR/documentation/architecture-check.sh" ]]; then
    # Run architecture check (always succeeds, just shows warnings)
    "$SCRIPTS_DIR/documentation/architecture-check.sh" || true
    echo -e "${GREEN}✓${NC} Architecture check completed"
else
    echo -e "${YELLOW}⚠${NC}  Architecture check script not found, skipping..."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAILED -eq 1 ]]; then
    echo -e "${RED}❌ Pre-push checks failed!${NC}"
    echo ""
    echo "Please fix the issues above before pushing."
    echo ""
    echo -e "${BLUE}💡 Need help?${NC} Ask Claude Code how to resolve these issues:"
    echo "   • Open Claude Code and describe the error message"
    echo "   • Claude Code can analyze and help fix the problems"
    echo ""
    echo "To bypass this check (not recommended), use: git push --no-verify"
    echo ""
    exit 1
else
    echo -e "${GREEN}✅ Pre-push checks passed!${NC}"
    echo ""
fi

exit 0
EOF

chmod +x "$HOOKS_DIR/pre-push"
echo -e "${GREEN}✓${NC} Pre-push hook installed"

# ============================================
# Record Setup Status
# ============================================
echo ""
echo "📝 Recording setup status..."

SETUP_FILE="$GIT_ROOT/.claude/settings.local.json"

# Function to safely extract JSON values (works without jq)
get_json_value() {
    local file=$1
    local key=$2
    if [[ -f "$file" ]]; then
        grep -o "\"$key\"[[:space:]]*:[[:space:]]*[^,}]*" "$file" | sed 's/.*:[[:space:]]*//;s/"//g;s/[[:space:]]*$//' | head -1
    fi
}

# Check if setup file exists and read existing values
if [[ -f "$SETUP_FILE" ]]; then
    CLAUDE_INSTALLED=$(get_json_value "$SETUP_FILE" "installed")
    CLAUDE_VERSION=$(get_json_value "$SETUP_FILE" "version")
    MCP_CONFIGURED=$(get_json_value "$SETUP_FILE" "configured")
    SETUP_COMPLETED=$(get_json_value "$SETUP_FILE" "completed")

    # Use existing values if they exist, otherwise use defaults
    CLAUDE_INSTALLED=${CLAUDE_INSTALLED:-false}
    CLAUDE_VERSION=${CLAUDE_VERSION:-unknown}
    MCP_CONFIGURED=${MCP_CONFIGURED:-false}
    SETUP_COMPLETED=${SETUP_COMPLETED:-false}
else
    # Default values for new setup
    CLAUDE_INSTALLED=false
    CLAUDE_VERSION="unknown"
    MCP_CONFIGURED=false
    SETUP_COMPLETED=false
fi

# Create or update settings.local.json
cat > "$SETUP_FILE" << EOF
{
  "setup": {
    "completed": $SETUP_COMPLETED,
    "claudeCode": {
      "installed": $CLAUDE_INSTALLED,
      "version": "$CLAUDE_VERSION"
    },
    "mcp": {
      "configured": $MCP_CONFIGURED
    },
    "gitHooks": {
      "installed": true
    },
    "setupDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}
EOF

echo -e "${GREEN}✓${NC} Setup status recorded in .claude/settings.local.json"

# ============================================
# Summary
# ============================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Git Hooks Setup Complete!${NC}"
echo ""
echo "Installed hooks:"
echo "  • pre-commit  → Version check, security, and language checks"
echo "  • commit-msg  → Commit message validation"
echo "  • pre-push    → Version check and comprehensive quality checks"
echo ""
echo "These hooks will now run automatically for all developers."
echo ""
echo "Version management:"
echo "  • Hooks automatically check tool versions before commits/pushes"
echo "  • Version mismatches are detected and can be fixed automatically"
echo "  • No manual version management needed!"
echo ""
echo "To bypass a hook (not recommended):"
echo "  git commit --no-verify"
echo "  git push --no-verify"
echo ""
echo "To complete full setup (Claude Code + MCP):"
echo "  ./.claude/scripts/setup/complete-setup.sh"
echo ""
echo "To update hooks in the future, run this script again."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
