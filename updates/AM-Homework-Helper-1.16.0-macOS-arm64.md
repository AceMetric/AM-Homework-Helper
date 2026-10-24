<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# AM Helper 1.16.0

构建 44 · 2026-10-24

- 修复暗色报告预览在加载、缩放和窗口调整时的白边，图片保留原色。
- “检查材料…”统一管理要求、题目、解答和参考材料，可添加 Markdown、图片及 PDF 所选页，并关联解答与原文范围。新增材料在发送前确认，不改变提交文件清单。
- 图片按 Markdown 中的章节和引用位置送入模型，同一图片保留多处引用；PDF 保留原始页码。
- 区分输出上限、内容拦截、空响应、无效结果及网络错误。完整结果逐组保存，达到输出上限才拆分；默认每次最多4次生成，可在发送前调整，重试同样计数。
- “继续检查”复用相同版本的已完成部分；取消、请求上限或保存失败不会被标为全部完成。缺少实际题目时明确保留答题对应关系和完整性检查限制。
- 底部只显示简短状态，具体错误集中在报告，上传副本在在线设置中管理。

Google 免费服务可能使用发送内容改进产品，请在发送前核对材料与页码。真实课程未用于自动云端验收。

当前构建为 Apple Silicon 版本，使用临时签名，未经 Apple 公证。
