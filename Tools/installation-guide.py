#!/usr/bin/env python3
import sys
from pathlib import Path

version = sys.argv[1]
Path(f'build/releases/DDL-Manager-{version}-安装说明.txt').write_text(f'''DDL-Manager {version} · macOS 13+ · Apple 芯片

此包使用临时签名，未经 Apple 公证。退出旧版，解压后将 DDL-Manager.app 拖入“应用程序”。首次打开若被阻止，在系统设置 → 隐私与安全性中按系统提示选择“仍要打开”。

本版加入“检查更新…”和“设置 → 软件更新”；默认每天检查，由你确认下载和安装。升级时等待课程操作结束，并处理未保存内容。正式更新清单尚未发布时，检查可能提示网络错误；不影响本机使用。

从侧栏“课程”开始连接 GitHub、选择个人 fork 和关联本地文件夹；“待审核作业”集中核对老师原文与截止时间。相对日期需确认完整截止时间。所有推送只到已核验属于当前用户的个人 fork。

旧测试版的数据与钥匙串授权继续沿用；原版 DDL Manager 请先导出备份，再导入。更新签名私钥不包含在应用中；登录令牌只存在本机钥匙串。

提醒需要系统通知权限；退出、关机或休眠时无法定时扫描。完整公开说明见 https://github.com/AceMetric/DDL-Manager 。
''')
