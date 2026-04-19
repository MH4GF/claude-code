# claude-code

MH4GF's Claude Code plugin marketplace.

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
```

## License

MIT
