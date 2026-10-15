<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# AM Helper 1.13.1

版本 1.13.1／构建33，macOS 13+、Apple 芯片，未经 Apple 公证。

## 课程检查布局修复

- 状态文字与取消按钮位于同一行，进度条独占下方一行，避免相互重叠。
- 按原生控件尺寸和外边距分配空间，兼容旧版 macOS；窄窗口、长状态文字及恢复与取消操作同时显示时保持分离。
- 检查完成后收起进度条和取消按钮，空闲时不保留空白进度区。

沿用 1.13.0 的周期任务、中国大陆日历、外部 Git 提交记录及 AI 识别与复核功能。已有任务、课程、备注、登录授权和更新签名继续兼容。

验证使用隔离模拟数据、临时仓库和模拟在线响应。macOS 14 自动回归覆盖控件边界、操作与布局；实际窗口外观及 macOS 13 实机、完整 VoiceOver 流程和正式下载安装仍由使用者核对。本版不代表真实在线模型质量获得新的验证。
