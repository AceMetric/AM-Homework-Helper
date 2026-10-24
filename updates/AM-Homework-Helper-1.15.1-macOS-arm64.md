<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# AM Helper 1.15.1

构建 43 · 2026-10-24

- 修复后台核验提交记录错误使用 30 秒网络时限的问题。网络核验共享最多 180 秒的总预算，取消仍立即生效。
- 后台失败后按课程和账户退避 5–30 分钟，保留手动重试；重启后继续遵守等待时间。
- 同一次课程核验的重复结果只展示一条；关闭相同错误后不反复弹出，原因变化时才重新提示。完整历史记录仍可查看。
- 明确提示“提交记录核验超时／现有记录保留”，成功重试后清除旧错误。
- 保留原提交、文件与远端核验要求，不重复提交或推送，不把未核验结果当作成功。

当前构建为 Apple Silicon 版本，使用临时签名，未经 Apple 公证。
