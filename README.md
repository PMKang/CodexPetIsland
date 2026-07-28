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

## 额度来源

额度采用分层读取：

1. 优先启动本机 Codex 自带的 `app-server`，调用官方
   `account/rateLimits/read` RPC。
2. 官方查询不可用时，比较最近一次成功结果的本地缓存与
   `~/.codex/sessions` 中最新的 `rate_limits` 事件，采用仍有效且
   更新的一份。

应用启动和手动刷新时会查询官方额度，常驻期间每 5 分钟查询一次。
会话文件变化只刷新任务和 Token 信息，不会高频启动 `app-server`。

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

应用不读取 `auth.json`，不上传提示词，也不修改宠物资源。额度查询通过
本机 Codex 自带的 `app-server` 完成；宠物岛本身不读取或传递访问令牌，
但 `app-server` 会使用 Codex 已有登录状态向其服务端刷新账户额度。

## 开发

```bash
./script/build_and_run.sh --verify
```

要求 macOS 14 或更高版本以及 Swift 6 工具链。
