<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# AM Helper 1.14.5

版本 1.14.5／构建41，适用于 Apple 芯片 Mac、macOS 13 及以上。

- 修复本地增强识别在等待完整回复时被60秒网络超时提前中断的问题。按材料长度设置105–180秒总预算，初次请求、兼容回退及一次纠正共用；仍可随时取消，不自动补发云端请求。
- 同一练习的章节、小题和步骤保留为一份作业；提示模型使用简短、连续的原文，避免复制整段数学题或拼接不相邻句子。提供材料路径和活动边界帮助定位，原文核验要求保持不变。
- 纠正无法提供依据的概括时允许清空该生成字段，保留活动及其他有效字段；修复纠正超时被最初核验错误掩盖的问题。
- 活动直接说明识别超时或具体核验原因，详情保留文件与原因，继续提供失败项重试。

不迁移任务数据库，不改写课程仓库。保留既有任务、已完成识别缓存和用户修改。应用使用临时签名，未经 Apple 公证。
