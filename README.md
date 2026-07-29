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

额度只通过本机 Codex 自带的 `app-server` 查询，调用官方
`account/rateLimits/read` RPC。不解析会话文件中的 `rate_limits`，
也不把额度结果缓存到磁盘；官方查询失败时保留本次运行期间最后一次
成功结果，应用重新启动后若仍无法查询则显示 `--`。

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

## 许可

本项目以仓库中的 MIT License 发布。额度功能只通过 JSON-RPC 调用本机
Codex 可执行文件，没有复制或打包 OpenAI Codex、CodexUsage、
codex-touchbar-usage 或 TokenBar 的源码，因此仓库中不附带这些项目的
版权声明。OpenAI Codex 本身采用 Apache-2.0，而不是 MIT。
