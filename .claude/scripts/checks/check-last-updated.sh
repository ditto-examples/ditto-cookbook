#!/bin/bash

# Check if best practices guides have updated "Last Updated" dates
# This script runs as part of pre-commit hook to ensure documentation timestamps are current

set -e

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Get today's date in YYYY-MM-DD format
TODAY=$(date +%Y-%m-%d)

# Files to check for "Last Updated" date
FILES_TO_CHECK=(
  ".claude/guides/best-practices/ditto.md"
  ".claude/guides/best-practices/flutter.md"
)

OUTDATED_FILES=()

# Check each file
for file in "${FILES_TO_CHECK[@]}"; do
  # Skip if file doesn't exist or isn't staged
  if [[ ! -f "$file" ]] || ! git diff --cached --name-only | grep -q "^$file$"; then
    continue
  fi

  # Extract last updated date from staged version
  LAST_UPDATED=$(git diff --cached "$file" | grep "^\+.*Last Updated" | tail -1 | sed 's/.*Last Updated.*: *//' | sed 's/[^0-9-]//g')

  # If no new Last Updated line in diff, check the file itself
  if [[ -z "$LAST_UPDATED" ]]; then
    LAST_UPDATED=$(grep "Last Updated" "$file" | tail -1 | sed 's/.*Last Updated.*: *//' | sed 's/[^0-9-]//g')
  fi

  # Check if date is today
  if [[ "$LAST_UPDATED" != "$TODAY" ]]; then
    OUTDATED_FILES+=("$file (Last Updated: ${LAST_UPDATED:-not found}, Expected: $TODAY)")
  fi
done

# Report results
if [[ ${#OUTDATED_FILES[@]} -gt 0 ]]; then
  echo ""
  echo -e "${YELLOW}⚠${NC}  Warning: Best practices guides may need updated timestamps"
  echo ""
  for file in "${OUTDATED_FILES[@]}"; do
    echo -e "  ${YELLOW}•${NC} $file"
  done
  echo ""
  echo -e "${YELLOW}→${NC} Consider updating 'Last Updated' dates to today ($TODAY)"
  echo -e "${YELLOW}→${NC} This is a reminder, not a blocking error"
  echo ""
fi

exit 0  # Non-blocking warning
