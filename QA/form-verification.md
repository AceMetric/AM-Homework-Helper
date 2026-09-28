# 5.3 表单配色验收

- 输入框、备注、光标、文字选区与焦点边框均使用当前主题，去除系统蓝色焦点光圈。
- 优先级、常用时间、提醒方案及主界面的排序、年月、配色选择器统一圆角与下拉箭头，展开菜单使用主题色选中态。
- 时间采用 HH:mm 输入与分钟微调按钮；保留常用时间和日期同步，错误输入阻止保存。
- 验证：98 项核心断言、53 项 AppKit 断言、60 项表单断言通过；严格告警编译、应用签名与 plist 检查通过。
- 独立预览实测：下箭头移动到 09:00，Return 确认后截止时间与具体时间均同步为 09:00；鼠标选择 18:00、直接输入 21:15 均正常。Esc 关闭菜单。
- 六套表单截图为 form-{sage,blue,lavender,rose,peach,cream}.png，全部使用演示任务。
- 原生菜单行需要接受 first responder 才能处理 Return，参考 Apple 的事件说明：https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/EventHandlingBasics/EventHandlingBasics.html

运行：`zsh verify-forms.sh`（需要 macOS 图形会话）。
