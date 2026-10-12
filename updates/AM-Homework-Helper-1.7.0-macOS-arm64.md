<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# AM's Homework Helper 1.7.0

## 提交前检查

- 提交改为“选择文件 → 检查结果 → 明确提交”，不会自动提交。
- 检查 Markdown 结构、未完成清单、图片缺失或损坏、Notebook 基本结构及可用时的 Python 语法；不运行作业代码。
- 检查的是 HEAD 加所选变更，未选中的新增附件会提示。修改文件后需复查，实际暂存版本还会再次核验。
- 可把文本、题目及 Markdown 引用的手写图片交给共用 Skill；预览材料后复制指令，结果自动回到报告，不创建新任务。
- 任务详情可只检查、不提交；提交记录保留简短检查摘要。

## 修复

- 修复已完成任务与异步提醒注册之间的竞争，清理完成、归档及删除任务的提醒；撤销完成后恢复有效提醒。
- 普通规则模式识别明确英文 Assignment 标题，即使没有截止说明也进入待审核，不虚构截止日期。
- 返回文件选择、检查失败、退出及更新时保留输入并提供明确反馈。

质量建议可以确认后继续；凭据检查、个人 fork 身份核验及禁止向老师仓库推送仍强制执行。助手复核不能保证答案一定正确，无法辨认的手写符号应留待核对。

macOS 13+，Apple 芯片；版本 1.7.0，构建 18。应用未经 Apple 公证，更新签名不等同于 Apple 公证。
