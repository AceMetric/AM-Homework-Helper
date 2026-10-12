<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# AM Helper 1.8.0

## 作业文件夹检查

- 任务详情“检查作业文件…”默认选择整个文件夹，包含子目录；仍可单独选择文件。
- 无需 GitHub 登录或 Git 仓库。先搜索、勾选文件范围，查看排除原因，再进行本机检查和可选助手复核。
- 独立检查读取当前本机文件；提交前检查仍使用 HEAD 加所选变更，避免检查与提交版本混用。
- 排除隐藏配置、敏感文件、依赖、缓存、构建目录和符号链接；Markdown 图片引用也受相同边界保护。
- 文件变化时显示报告过期，可调整范围并重新检查。保留格式、缺失图片、未完成项、基本语法和拼写建议；答案正确性由可选助手复核。

## 引导与界面

- 欢迎页可选择“先使用本机作业功能”，稍后再连接课程。
- 一次“确认并开始检查”完成目录核验、关联与首次检查；失败可重试，关闭引导保留进度。
- 后台读取完成不会重新弹出已关闭的引导；首次检查取消后显示明确的恢复入口。
- “开始使用”改为应用内帮助页，清楚区分发现老师的新作业、检查自己的文件、同步及提交。
- 统一 AppKit 与 SwiftUI 的背景、按钮、标题和提示，检查范围与报告适配浅深外观及较窄窗口。

仍适用于 macOS 13+、Apple 芯片。使用临时签名，未经 Apple 公证。已有任务、课程、登录与更新公钥保持兼容；检查不会执行代码或自动提交，作业推送始终限定为已核验的个人 fork。
