<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# AM Helper 1.7.2

修复“检查作业”被后台自动扫描拦住、或打开后等待扫描结束的问题。

- 只读作业检查使用独立队列，后台读取老师仓库或模型分析不再阻止检查。
- 留在当前任务页面，选完文件直接显示检查进度和报告；已完成任务也可复查。
- Git写入、已有编辑窗口或准备退出／更新时仍受保护，并说明具体原因。
- Markdown引用图片自动纳入检查，可选择共用Skill深入复核；不会自动修改答案、提交或推送。

兼容原有任务、课程、登录与更新设置。适用于macOS 13+、Apple芯片。应用使用临时签名，未经Apple公证。
