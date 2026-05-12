# Claude Launcher

Switch Claude Code model presets from an interactive terminal menu.

A single script. No dependencies beyond bash and jq (or python3).

[中文文档](README.zh.md)

## Quick Start

```bash
./install.sh
# Edit ~/.config/claude-launcher/presets.json to fill in your API keys
claude-launcher
```

## Usage

```
install.sh                     Install to ~/.config/claude-launcher/
claude-launcher                Launch: select preset → start Claude Code
claude-launcher models         Manage presets (list, add, edit, remove)
claude-launcher uninstall      Remove everything
claude-launcher -h             Help
```

### Per-project config

```bash
CLAUDE_LAUNCHER_CONFIG=./my-presets.json claude-launcher
```

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `CLAUDE_LAUNCHER_CONFIG` | Custom path to presets.json |
| `CLAUDE_LAUNCHER_NO_COLOR` | Disable colored output |
| `NO_COLOR` | Disable colored output (standard) |

## Configuration

`~/.config/claude-launcher/presets.json`:

```json
{
  "version": "1",
  "presets": [
    {
      "name": "MiniMax M2.7",
      "env": {
        "ANTHROPIC_BASE_URL": "https://api.minimaxi.com/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "YOUR_API_KEY",
        "ANTHROPIC_MODEL": "MiniMax-M2.7",
        "ANTHROPIC_SMALL_FAST_MODEL": "MiniMax-M2.7",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "MiniMax-M2.7",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "MiniMax-M2.7",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "MiniMax-M2.7",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
      }
    }
  ]
}
```

The `env` object accepts any key-value pairs.

## Security

Tokens stored at `~/.config/claude-launcher/presets.json` (permissions 600). Never commit this file.
