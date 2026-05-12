# Claude Launcher / Claude 启动器

Switch Claude Code model presets from an interactive terminal menu.
通过交互式终端菜单切换 Claude Code 的模型预设。

A single script. No dependencies beyond bash and jq (or python3).
单脚本，除 bash 和 jq（或 python3）外无其他依赖。

## Quick Start / 快速开始

```bash
./install.sh
# Edit 编辑 ~/.config/claude-launcher/presets.json to fill in your API keys 填入你的 API Key
claude-launcher
```

## Usage / 使用方式

```
install.sh                     安装到 ~/.config/claude-launcher/
claude-launcher                启动：选择预设 → 启动 Claude Code
claude-launcher models         管理预设（查看、新增、编辑、删除）
claude-launcher uninstall      完全卸载
claude-launcher -h             帮助
```

### Per-project config / 项目级配置

```bash
CLAUDE_LAUNCHER_CONFIG=./my-presets.json claude-launcher
```

### Environment Variables / 环境变量

| Variable | Purpose / 用途 |
|----------|---------|
| `CLAUDE_LAUNCHER_CONFIG` | 自定义 presets.json 路径 |
| `CLAUDE_LAUNCHER_NO_COLOR` | 禁用彩色输出 |
| `NO_COLOR` | 禁用彩色输出（通用标准） |

## Configuration / 配置

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

The `env` object accepts any key-value pairs. / `env` 对象支持任意键值对。

## Security / 安全

Tokens stored at / Token 存储在 `~/.config/claude-launcher/presets.json` (permissions 600). Never commit this file. / 切勿提交此文件。
