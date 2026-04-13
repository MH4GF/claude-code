# claude-code

MH4GF's Claude Code plugin marketplace.

## Plugins

### hook-logging

JSONL logging of all Claude Code hook events (PreToolUse, PostToolUse, PermissionRequest, PermissionDenied) with aggregation and analysis.

#### Installation

Add to `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "hook-logging@claude-code": true
  },
  "extraKnownMarketplaces": {
    "claude-code": {
      "source": {
        "source": "github",
        "repo": "MH4GF/claude-code"
      },
      "autoUpdate": true
    }
  }
}
```

#### What it does

- Logs every hook event to `~/.claude/logs/<session_id>.jsonl`
- Truncates long strings in `tool_input` at 2048 characters
- Strips `tool_response` body, keeping only `is_error` flag (secrets & size protection)
- Never blocks tool execution (silent, always exit 0)

#### Slash Commands

- `/analyze-hook-logs [days]` - Aggregate and analyze hook logs, suggest improvements to settings.json, CLAUDE.md, scripts, and hooks

#### Utility Scripts

- `scripts/aggregate-hook-logs.sh --since N --format json|md` - Aggregate logs with invocation grouping and ask_flow derivation
- `scripts/rotate-hook-logs.sh [days]` - Delete log files older than N days (default: 14)

#### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_LOG_DIR` | `~/.claude/logs` | Directory for JSONL log files |
| `CLAUDE_SETTINGS` | `~/.claude/settings.json` | Settings file for permission cross-reference |

## Development

### Run Tests

```bash
bash tests/test-log-hook.sh      # Logger unit tests (9 cases)
bash tests/test-aggregate.sh     # Aggregation smoke tests (17 cases)
```

## License

MIT
