# claude-code

MH4GF's Claude Code plugin marketplace.

## Plugins

### tool-use-steering

Steering loop for Claude Code harness: log tool-use events, aggregate invocations, and AI-driven analysis to continuously improve settings.json, CLAUDE.md, hooks, and scripts.

Based on the [harness engineering](https://martinfowler.com/articles/harness-engineering.html) framework — automates the steering loop by instrumenting tool-use hook events, deterministically aggregating invocations, and letting Claude classify and apply improvements.

#### Installation

Add to `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "tool-use-steering@claude-code": true
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

#### 3-Layer Architecture

```
[1] log-hook-event.sh       ─── JSONL instrumentation
[2] aggregate-hook-logs.sh  ─── Deterministic aggregation
[3] /analyze-hook-logs      ─── AI-driven steering
```

1. **Instrumentation**: Logs all 4 hook events (PreToolUse/PostToolUse/PermissionRequest/PermissionDenied) to `~/.claude/logs/<session_id>.jsonl`
2. **Aggregation**: Groups by invocation, derives ask_flow states (auto_allowed/user_allowed/user_denied/auto_denied), cross-references with current settings
3. **Analysis**: Claude reads the aggregation, classifies improvements across settings.json, CLAUDE.md, scripts, and hooks, then applies them interactively

#### Slash Commands

- `/tool-use-steering:improve [days]` - Analyze tool-use logs and interactively apply harness improvements

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
