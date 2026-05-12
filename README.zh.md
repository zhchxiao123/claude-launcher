# Claude Launcher / Claude 启动器

通过交互式终端菜单切换 Claude Code 的模型预设。

单脚本，除 bash 和 jq（或 python3）外无其他依赖。

安装脚本会自动检测缺失组件，并提供通过系统包管理器一键安装（支持 Homebrew / apt / yum / dnf / pacman / apk）。

[English](README.md)

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/zhchxiao123/claude-launcher/main/install.sh | bash
claude-launcher
```

或者克隆后安装：

```bash
git clone https://github.com/zhchxiao123/claude-launcher.git && cd claude-launcher
./install.sh
claude-launcher
```

## 使用方式

```
install.sh                     安装到 ~/.config/claude-launcher/
claude-launcher                启动：选择预设 → 启动 Claude Code
claude-launcher models         管理预设（查看、新增、编辑、删除）
claude-launcher uninstall      完全卸载
claude-launcher -h             帮助
```

### 项目级配置

```bash
CLAUDE_LAUNCHER_CONFIG=./my-presets.json claude-launcher
```

### 环境变量

| 变量 | 用途 |
|----------|---------|
| `CLAUDE_LAUNCHER_CONFIG` | 自定义 presets.json 路径 |
| `CLAUDE_LAUNCHER_NO_COLOR` | 禁用彩色输出 |
| `NO_COLOR` | 禁用彩色输出（通用标准） |

## 配置

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

`env` 对象支持任意键值对。

## 安全

Token 存储在 `~/.config/claude-launcher/presets.json`（权限 600）。切勿提交此文件。
