# Codex Pet Island

一个独立、原生、仅本地运行的 macOS Codex 桌面宠物。

它读取本机 Codex / OpenCode 会话与自定义宠物，在透明悬浮窗中展示：

- 当前本地宠物及原始精灵动画
- Codex 周额度剩余比例与重置倒计时
- OpenCode Go 5 小时 / 每周用量比例与重置倒计时
- Codex 与 OpenCode Go 的最新任务与运行状态
- 可拖动、多显示器、屏幕边缘吸附
- 75%～300% 宠物缩放
- 中英文界面
- 可由宠物包声明独立的 subagent 形态

## 额度来源

Codex 额度通过本机 Codex 自带的 `app-server` 查询，调用官方
`account/rateLimits/read` RPC。OpenCode Go 额度通过官方
`https://opencode.ai/zen/go/v1/usage` 查询，Key 由用户在菜单中输入并
保存到 macOS Keychain。两者都不解析会话文件中的额度字段，也不把额度
结果缓存到磁盘；查询失败时保留当前运行期间最后一次成功结果。

应用启动和手动刷新时查询官方额度，常驻期间每 5 分钟查询一次。会话
文件或 OpenCode SQLite 数据库变化只刷新任务，不会高频请求额度接口。

## 可选 subagent 形态

宠物包可以在 `pet.json` 中声明一张独立形态图片；应用不会按宠物名称
写死外观。检测到运行中的 subagent 时才显示该资源，普通任务仍使用标准
spritesheet 的 `running` 行。

```json
{
  "subagentFormPath": "forms/subagent.png",
  "subagentScaleMultiplier": 1.5
}
```

`subagentFormPath` 必须指向当前宠物包目录内的透明 PNG/WebP。

## 隐私

应用直接读取：

- `~/.codex/config.toml`
- `~/.codex/pets/*/pet.json`
- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/session_index.jsonl`
- `~/.local/share/opencode/opencode.db`

应用不读取 OpenCode `auth.json`，不上传提示词，也不修改宠物资源。
OpenCode Go Key 只从 macOS Keychain 读取，并仅作为官方用量接口的
Bearer 凭据使用。

## 开发

```bash
./script/build_and_run.sh --verify
```

要求 macOS 14 或更高版本以及 Swift 6 工具链。

## 许可

本项目以仓库中的 MIT License 发布。额度功能只通过 JSON-RPC 调用本机
Codex 可执行文件，没有复制或打包 OpenAI Codex、CodexUsage、
codex-touchbar-usage 或 TokenBar 的源码，因此仓库中不附带这些项目的
版权声明。OpenAI Codex 本身采用 Apache-2.0，而不是 MIT。
