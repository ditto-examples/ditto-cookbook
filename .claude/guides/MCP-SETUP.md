# MCP Servers Setup

This guide covers setup of Model Context Protocol (MCP) servers for enhanced AI-assisted development with Ditto and Flutter.

## Quick Automated Setup (Recommended)

The fastest way to configure both MCP servers:

```bash
./.claude/scripts/setup/setup-mcp-servers.sh
```

This script will:
1. Configure Ditto MCP server (documentation access)
2. Download and configure Flutter MCP server (Flutter/Dart support)
3. Verify installation and provide next steps

**After running the script, restart Claude Code for changes to take effect.**

---

## Manual Setup

### Ditto MCP Server

Add Ditto documentation access to Claude:

```bash
claude mcp add --transport http Ditto https://docs.ditto.live/mcp
```

**What it provides:**
- Access to Ditto SDK documentation
- Code examples and best practices
- API reference and guides
- Real-time sync patterns

### Flutter MCP Server

#### Option 1: Using Setup Script (Recommended)
The automated script handles platform detection and binary download automatically.

#### Option 2: Manual Installation

1. **Download the Flutter MCP binary** for your platform:
   - macOS (Apple Silicon): https://github.com/flutter-mcp/flutter-mcp/releases/latest/download/flutter-mcp-macos
   - macOS (Intel): https://github.com/flutter-mcp/flutter-mcp/releases/latest/download/flutter-mcp-macos-intel
   - Linux: https://github.com/flutter-mcp/flutter-mcp/releases/latest/download/flutter-mcp-linux
   - Windows: https://github.com/flutter-mcp/flutter-mcp/releases/latest/download/flutter-mcp-windows.exe

2. **Make it executable** (macOS/Linux):
   ```bash
   chmod +x flutter-mcp
   ```

3. **Configure MCP server**:
   ```bash
   claude mcp add flutter-mcp /absolute/path/to/flutter-mcp
   ```

**What it provides:**
- Flutter and Dart code assistance
- Widget recommendations
- Best practices for Flutter development
- Debugging support

---

## Verification

Check that both servers are configured:

```bash
claude mcp list
```

You should see:
- `Ditto` (http transport)
- `flutter-mcp` (stdio transport)

---

## Using MCP Servers with Claude

Once configured, Claude can automatically access:

**Ditto Documentation:**
- Search Ditto docs without leaving your workflow
- Get accurate API examples
- Learn sync strategies and best practices

**Flutter Support:**
- Widget and API recommendations
- Platform-specific guidance (iOS, Android, Web)
- Flutter package suggestions
- Dart language help

**Example prompts:**
- "How do I configure Ditto sync subscriptions?"
- "Show me best practices for Flutter state management"
- "What's the recommended way to handle offline data with Ditto?"

---

## Troubleshooting

### MCP Server Not Found

**Issue:** `claude mcp list` doesn't show your servers

**Solutions:**
1. Restart Claude Code completely (not just reload window)
2. Check configuration file:
   - macOS/Linux: `~/.config/claude/mcp_servers.json`
   - Windows: `%APPDATA%\claude\mcp_servers.json`
3. Verify Claude Code CLI is up to date: `claude --version`

### Ditto MCP Connection Issues

**Issue:** Ditto MCP server fails to connect

**Solutions:**
1. Verify internet connectivity
2. Check firewall settings
3. Try removing and re-adding:
   ```bash
   claude mcp remove Ditto
   claude mcp add --transport http Ditto https://docs.ditto.live/mcp
   ```

### Flutter MCP Binary Not Working

**Issue:** Flutter MCP server fails to start

**Solutions:**
1. Verify binary is executable: `chmod +x flutter-mcp`
2. Check binary architecture matches your system:
   ```bash
   uname -m  # Should match binary (arm64 or x86_64)
   ```
3. Download correct binary for your platform
4. Verify full path in MCP configuration (no ~, use absolute path)

### Permission Denied Errors

**Issue:** Cannot execute flutter-mcp binary

**Solutions:**
1. macOS: Remove quarantine attribute:
   ```bash
   xattr -d com.apple.quarantine flutter-mcp
   chmod +x flutter-mcp
   ```
2. Linux: Ensure binary has execute permissions:
   ```bash
   chmod +x flutter-mcp
   ```
3. Windows: Right-click > Properties > Unblock

### MCP Server Keeps Restarting

**Issue:** Server appears in list but keeps restarting

**Solutions:**
1. Check Claude Code logs for error messages
2. Verify binary path is correct (absolute path)
3. For Flutter MCP: Ensure Flutter SDK is installed and in PATH
4. Try running binary manually to see error output:
   ```bash
   /path/to/flutter-mcp
   ```

---

## Full Documentation

For comprehensive setup instructions, advanced configuration, and detailed troubleshooting:

- **MCP Protocol:** https://modelcontextprotocol.io
- **Ditto MCP:** https://docs.ditto.live/mcp
- **Flutter MCP:** https://github.com/flutter-mcp/flutter-mcp
- **Claude Code MCP Guide:** https://docs.anthropic.com/claude/mcp

---

## Team Onboarding

When onboarding new team members:

1. **Share this guide** from the repository
2. **Run automated setup:**
   ```bash
   git clone <repository>
   cd <project>
   ./.claude/scripts/setup/setup-mcp-servers.sh
   ```
3. **Restart Claude Code**
4. **Verify with:** `claude mcp list`

Automated setup takes 1-2 minutes and ensures consistency across the team.

---

## Updating MCP Servers

### Ditto MCP
Ditto MCP updates automatically (HTTP-based). No manual updates needed.

### Flutter MCP
To update to the latest version:

1. **Remove existing server:**
   ```bash
   claude mcp remove flutter-mcp
   ```

2. **Download latest binary** from releases page

3. **Re-add with new binary:**
   ```bash
   claude mcp add flutter-mcp /path/to/new/flutter-mcp
   ```

4. **Restart Claude Code**

---

## Uninstalling

To remove MCP servers:

```bash
# Remove Ditto MCP
claude mcp remove Ditto

# Remove Flutter MCP
claude mcp remove flutter-mcp
rm /path/to/flutter-mcp  # Delete binary
```

Restart Claude Code after removing servers.
