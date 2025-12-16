#!/usr/bin/env bash
# Central Configuration for Claude Code Scripts
#
# This file contains centralized configuration values used across all scripts
# in the repository. Source this file in any script that needs these values.
#
# Usage:
#   source "$PROJECT_ROOT/.claude/scripts/config.sh"

# Project discovery paths
export APP_SEARCH_DIRS=("apps/flutter" "apps/ios" "apps/android" "apps/web")
export TOOL_SEARCH_DIRS=("tools")

# Timeouts (in seconds)
export TEST_TIMEOUT_SECONDS=1800
export DEPENDENCY_CHECK_TIMEOUT=300

# Script paths (relative to PROJECT_ROOT)
export DEPENDENCY_MANAGERS_DIR=".claude/scripts/maintenance/dependency-managers"
export TEST_RUNNERS_DIR=".claude/scripts/testing/runners"

# Platform constants
readonly PLATFORM_FLUTTER="flutter"
readonly PLATFORM_IOS="ios"
readonly PLATFORM_ANDROID="android"
readonly PLATFORM_NODE="node"
readonly PLATFORM_PYTHON="python"
readonly PLATFORM_UNKNOWN="unknown"

# Command constants
readonly CMD_CHECK="check"
readonly CMD_UPDATE="update"

# Dependency file names
readonly FLUTTER_DEPS_FILE="pubspec.yaml"
readonly IOS_DEPS_FILE="Podfile"
readonly ANDROID_DEPS_FILE="build.gradle"
readonly NODE_DEPS_FILE="package.json"
readonly PYTHON_DEPS_FILE="requirements.txt"
