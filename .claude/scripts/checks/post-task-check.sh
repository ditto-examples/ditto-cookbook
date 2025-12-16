#!/usr/bin/env bash

# Post-Task Quality Check Script
# Runs automatically after task completion to ensure consistency

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source test helpers for consistent formatting
source "$PROJECT_ROOT/.claude/scripts/testing/utils/test-helpers.sh"

echo ""
echo "🔍 Running Post-Task Quality Checks..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Track issues
ISSUES_FOUND=0

# ============================================
# Cache Git Information (run once)
# ============================================
IS_GIT_REPO=false
GIT_STATUS_OUTPUT=""
MODIFIED_FILES=""

if git rev-parse --git-dir > /dev/null 2>&1; then
    IS_GIT_REPO=true
    GIT_STATUS_OUTPUT=$(git status -s 2>/dev/null || echo "")
    MODIFIED_FILES=$(git diff --name-only HEAD 2>/dev/null || git ls-files 2>/dev/null || echo "")
fi

# ============================================
# Function Definitions (for external calling)
# ============================================

run_security_check() {
    echo ""
    echo -e "${BLUE}[2/6]${NC} Scanning for potential secrets..."

    local SECURITY_ISSUES=0

    # Check for common secret patterns in recently modified files
    if $IS_GIT_REPO; then
        if [[ -n "$MODIFIED_FILES" ]]; then
            while IFS= read -r file; do
                # Skip security check scripts themselves to avoid false positives
                if [[ "$file" == *"security-check.sh"* ]] || [[ "$file" == *"post-task-check.sh"* ]]; then
                    continue
                fi

                if [[ -f "$file" ]]; then
                    # Check for API keys
                    if grep -qiE "(api[_-]?key|apikey|api[_-]?secret)" "$file" 2>/dev/null; then
                        if grep -qiE "(api[_-]?key|apikey|api[_-]?secret)\s*[:=]\s*['\"][a-zA-Z0-9_-]{20,}['\"]" "$file" 2>/dev/null; then
                            echo -e "${RED}✗${NC} Possible API key found in: $file"
                            SECURITY_ISSUES=$((SECURITY_ISSUES + 1))
                        fi
                    fi

                    # Check for hardcoded credentials
                    if grep -qiE "(password|passwd|pwd)\s*[:=]\s*['\"][^'\"]+['\"]" "$file" 2>/dev/null; then
                        echo -e "${RED}✗${NC} Possible hardcoded password in: $file"
                        SECURITY_ISSUES=$((SECURITY_ISSUES + 1))
                    fi

                    # Check for cryptographic keys (RSA, etc.)
                    if grep -q "BEGIN.*PRIVATE KEY" "$file" 2>/dev/null; then
                        echo -e "${RED}✗${NC} Private key found in: $file"
                        SECURITY_ISSUES=$((SECURITY_ISSUES + 1))
                    fi
                fi
            done <<< "$MODIFIED_FILES"
        fi
    fi

    if [[ $SECURITY_ISSUES -gt 0 ]]; then
        echo -e "${RED}⚠ ${SECURITY_ISSUES} potential security issue(s) found!${NC}"
        echo -e "${YELLOW}→${NC} Review and remove any exposed secrets before committing"
    else
        echo -e "${GREEN}✓${NC} No obvious secrets detected"
    fi

    # Check .env file security
    local ENV_ISSUES=0

    # Check if .env is tracked in git
    if $IS_GIT_REPO; then
        if git ls-files --error-unmatch .env 2>/dev/null; then
            echo -e "${RED}✗${NC} .env file is tracked in git!"
            echo -e "${YELLOW}→${NC} Run: git rm --cached .env && echo '.env' >> .gitignore"
            ENV_ISSUES=$((ENV_ISSUES + 1))
        fi
    fi

    # Check if .env and template are in sync
    if [[ -f ".env" ]]; then
        local ENV_TEMPLATE=""
        if [[ -f ".env.template" ]]; then
            ENV_TEMPLATE=".env.template"
        elif [[ -f ".env.example" ]]; then
            ENV_TEMPLATE=".env.example"
        fi

        if [[ -n "$ENV_TEMPLATE" ]]; then
            local ENV_KEYS=$(grep -E "^[A-Z_]+" .env 2>/dev/null | cut -d= -f1 | sort || true)
            local TEMPLATE_KEYS=$(grep -E "^[A-Z_]+" "$ENV_TEMPLATE" 2>/dev/null | cut -d= -f1 | sort || true)

            if [[ "$ENV_KEYS" != "$TEMPLATE_KEYS" ]]; then
                echo -e "${YELLOW}⚠${NC}  .env and $ENV_TEMPLATE are not synchronized"
                local MISSING=$(comm -23 <(echo "$ENV_KEYS") <(echo "$TEMPLATE_KEYS"))
                local EXTRA=$(comm -13 <(echo "$ENV_KEYS") <(echo "$TEMPLATE_KEYS"))
                if [[ -n "$MISSING" ]]; then
                    echo -e "${YELLOW}→${NC} Missing in $ENV_TEMPLATE: $(echo $MISSING | tr '\n' ' ')"
                fi
                if [[ -n "$EXTRA" ]]; then
                    echo -e "${YELLOW}→${NC} Extra in $ENV_TEMPLATE: $(echo $EXTRA | tr '\n' ' ')"
                fi
                ENV_ISSUES=$((ENV_ISSUES + 1))
            fi
        elif [[ -f ".env" ]]; then
            echo -e "${YELLOW}⚠${NC}  .env exists but no .env.template or .env.example found"
            echo -e "${YELLOW}→${NC} Create template file to document required environment variables"
            ENV_ISSUES=$((ENV_ISSUES + 1))
        fi
    fi

    local TOTAL_ISSUES=$((SECURITY_ISSUES + ENV_ISSUES))
    return $TOTAL_ISSUES
}

run_language_check() {
    echo ""
    echo -e "${BLUE}[3/6]${NC} Checking for non-English content..."

    local NON_ENGLISH=0

    if $IS_GIT_REPO; then
        if [[ -n "$MODIFIED_FILES" ]]; then
            while IFS= read -r file; do
                if [[ -f "$file" && "$file" =~ \.(md|dart|js|ts|tsx|jsx|java|kt|swift|py|txt)$ ]]; then
                    # Check for Japanese characters (Hiragana, Katakana, Kanji)
                    if grep -qP '[\p{Hiragana}\p{Katakana}\p{Han}]' "$file" 2>/dev/null; then
                        echo -e "${YELLOW}⚠${NC}  Non-English content in: $file"
                        NON_ENGLISH=$((NON_ENGLISH + 1))
                    fi
                fi
            done <<< "$MODIFIED_FILES"
        fi
    fi

    if [[ $NON_ENGLISH -gt 0 ]]; then
        echo -e "${YELLOW}⚠ ${NON_ENGLISH} file(s) contain non-English content${NC}"
        echo -e "${YELLOW}→${NC} Verify this is intentional (e.g., test data, user-facing text)"
    else
        echo -e "${GREEN}✓${NC} All checked files use English"
    fi

    return $NON_ENGLISH
}

# ============================================
# Main Execution (when run directly)
# ============================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Only run full checks if executed directly (not when sourced)

# ============================================
# 1. Check for Uncommitted Changes
# ============================================
echo ""
echo -e "${BLUE}[1/6]${NC} Checking git status..."

if $IS_GIT_REPO; then
    if [[ -n "$GIT_STATUS_OUTPUT" ]]; then
        echo -e "${YELLOW}⚠${NC}  Uncommitted changes detected:"
        echo "$GIT_STATUS_OUTPUT" | head -10
        if [[ $(echo "$GIT_STATUS_OUTPUT" | wc -l) -gt 10 ]]; then
            echo "    ... and $(($(echo "$GIT_STATUS_OUTPUT" | wc -l) - 10)) more files"
        fi
        echo -e "${YELLOW}→${NC} Consider committing your changes"
    else
        echo -e "${GREEN}✓${NC} No uncommitted changes"
    fi
else
    echo -e "${YELLOW}⚠${NC}  Not a git repository"
fi

# ============================================
# 2. Security Check - Scan for Secrets
# ============================================
run_security_check
SECURITY_RESULT=$?
ISSUES_FOUND=$((ISSUES_FOUND + SECURITY_RESULT))

# ============================================
# 3. Language Check - Ensure English Only
# ============================================
run_language_check
LANGUAGE_RESULT=$?
ISSUES_FOUND=$((ISSUES_FOUND + LANGUAGE_RESULT))

# ============================================
# 4. Flutter/Dart Checks (if applicable)
# ============================================
echo ""
echo -e "${BLUE}[4/6]${NC} Running Flutter/Dart checks..."

if command -v dart &> /dev/null; then
    if [[ -f "pubspec.yaml" ]]; then
        echo "→ Running dart analyze..."
        if dart analyze --fatal-infos 2>&1 | grep -q "error"; then
            echo -e "${RED}✗${NC} Dart analysis found errors"
            dart analyze --fatal-infos 2>&1 | grep "error" | head -5
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        else
            echo -e "${GREEN}✓${NC} Dart analysis passed"
        fi
    else
        echo -e "${YELLOW}⚠${NC}  No pubspec.yaml found, skipping Dart checks"
    fi
else
    echo -e "${YELLOW}⚠${NC}  Dart not installed, skipping Dart checks"
fi

# ============================================
# 5. Documentation Check
# ============================================
echo ""
echo -e "${BLUE}[5/6]${NC} Checking documentation..."

DOC_ISSUES=0

# Check if README.md exists and is not empty
if [[ ! -f "README.md" ]]; then
    echo -e "${YELLOW}⚠${NC}  README.md not found"
    DOC_ISSUES=$((DOC_ISSUES + 1))
elif [[ ! -s "README.md" ]]; then
    echo -e "${YELLOW}⚠${NC}  README.md is empty"
    DOC_ISSUES=$((DOC_ISSUES + 1))
else
    echo -e "${GREEN}✓${NC} README.md exists and has content"
fi

# Check for TODO comments in modified files
if $IS_GIT_REPO; then
    TODO_COUNT=$(git diff HEAD 2>/dev/null | grep -c "^+.*TODO" || true)
    if [[ $TODO_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}⚠${NC}  $TODO_COUNT new TODO comment(s) added"
        echo -e "${YELLOW}→${NC} Consider creating issues for these TODOs"
    fi
fi

if [[ $DOC_ISSUES -eq 0 ]]; then
    echo -e "${GREEN}✓${NC} Documentation check passed"
fi

# ============================================
# 6. Code Quality Reminders
# ============================================
echo ""
echo -e "${BLUE}[6/6]${NC} Code quality checklist..."
echo ""
echo "Please verify:"
echo "  • Error handling implemented for external APIs"
echo "  • Input validation added where necessary"
echo "  • Tests added/updated for critical functionality"
echo "  • Comments added only where logic isn't self-evident"
echo "  • No over-engineering (keep it simple)"

# ============================================
# Summary
# ============================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $ISSUES_FOUND -gt 0 ]]; then
    echo -e "${YELLOW}⚠ Quality Check Complete: ${ISSUES_FOUND} issue(s) found${NC}"
    echo ""
    echo "Please review the issues above before proceeding."
    echo "These checks help maintain code quality and security."
else
    echo -e "${GREEN}✓ Quality Check Complete: No issues found${NC}"
    echo ""
    echo "Great work! Your changes look good."
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Return 0 always - This is an informational check only, not a blocker
# The purpose is to remind developers of quality standards, not prevent work
# For CI/CD environments requiring strict checks, use dedicated check scripts
# that exit with non-zero codes on violations
exit 0

fi  # End of main execution block
