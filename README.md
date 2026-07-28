# Codex Pet Island

一个独立、原生、仅本地运行的 macOS Codex 桌面宠物。

它读取本机 Codex 自定义宠物与会话日志，在透明悬浮窗中展示：

- 当前本地宠物及原始精灵动画
- Codex 周额度剩余比例与重置倒计时
- 最近任务与运行状态
- 可拖动、多显示器、屏幕边缘吸附
- 75%～300% 宠物缩放
- 中英文界面
- 可由宠物包声明独立的 subagent 形态

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

应用只读取：

- `~/.codex/config.toml`
- `~/.codex/pets/*/pet.json`
- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/session_index.jsonl`

它不读取 `auth.json`，不上传提示词，不发起网络请求，也不修改宠物资源。

## 开发

```bash
./script/build_and_run.sh --verify
```

要求 macOS 14 或更高版本以及 Swift 6 工具链。
