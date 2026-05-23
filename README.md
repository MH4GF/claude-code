# claude-code

MH4GF's Claude Code configuration and plugin marketplace.

This repository hosts both publicly distributed plugins (`.claude-plugins/`) and personal user scope settings (`user-scope/`) symlinked into `~/.claude/`.

## Plugins

- **[tool-use-steering](.claude-plugins/tool-use-steering/)** — Steering loop for Claude Code harness: log tool-use events, aggregate invocations, and AI-driven analysis to continuously improve settings.json, CLAUDE.md, hooks, and scripts.

## User scope config

`user-scope/` contains user scope Claude Code settings (`CLAUDE.md`, `settings.json`, `commands/`, `skills/`, `hooks/`). Run `./setup.sh` to symlink them into `~/.claude/`.

```bash
./setup.sh
```

## Development

### Run Tests

```bash
bash tests/test-log-hook.sh      # Logger unit tests (9 cases)
bash tests/test-aggregate.sh     # Aggregation smoke tests (17 cases)
bash tests/test-comment-guard.sh # Comment-guard hook tests (25 cases)
```

## License

MIT
