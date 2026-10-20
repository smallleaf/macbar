# MacBar

macOS 菜单栏图标管理器。打开应用即可查看菜单栏中的所有图标，并将不常用的图标隐藏到「隐藏区」或「始终隐藏区」。

- 系统要求：macOS 14 及以上（已在 macOS 26.2 验证）
- 技术栈：Swift 6 / AppKit + SwiftUI，无第三方依赖

## 功能

| 功能 | 说明 |
|---|---|
| 菜单栏图标列表 | 扫描并展示所有状态项，支持搜索与按分区筛选 |
| 隐藏 / 显示 | 单击图标切换；右键可移动到显示区、隐藏区、始终隐藏区 |
| 批量操作 | 全部隐藏、全部显示、重置布局 |
| 布局持久化 | 记录分区与原始位置，重启后对账并自动修复偏差 |
| 权限引导 | 缺少「辅助功能」时进入只读模式，并给出修复步骤 |
| 诊断 | 环境信息、状态项坐标、最近操作日志，可一键导出 |
| 快捷键 | `⌥⌘H` 切换隐藏区，`⌥⌘⇧R` 紧急恢复全部图标 |

## 构建

```bash
swift build -c release          # 编译
swift test                      # 单元测试
Scripts/build.sh release        # 生成 dist/MacBar.app 并签名
Scripts/make_dmg.sh             # 打包 DMG 与 SHA256
Scripts/verify.sh               # 测试 + 构建 + 运行时自检
```

`Scripts/build.sh` 会自动查找本机证书（优先 Developer ID，其次 Apple Development）。
使用证书签名时，辅助功能授权在重新构建后依然有效；若只能 ad-hoc 签名，每次重新构建都会使授权失效，应用会在界面上提示重新添加。

发布前需要在带 `Developer ID Application` 证书的机器上执行：

```bash
Scripts/build.sh release --sign "Developer ID Application: <组织> (<TEAM>)"
Scripts/notarize.sh dist/MacBar.app   # 需要预先执行 notarytool store-credentials
Scripts/make_dmg.sh
```

## 运行时自检

```bash
dist/MacBar.app/Contents/MacOS/MacBar --self-check   # 只读扫描菜单栏并输出报告
dist/MacBar.app/Contents/MacOS/MacBar --smoke 8      # 启动完整应用并在 8 秒后退出
```

## 安装后的必要设置

1. **把应用放到「应用程序」文件夹后再启动。** 从 DMG 或临时目录直接运行，系统会把状态项当作匿名进程处理，图标不会进入菜单栏。
2. **系统设置 → 菜单栏 → 允许在菜单栏中显示：启用 MacBar。** 从 macOS 26 起菜单栏由系统统一托管，该开关关闭时图标不会出现。若已开启仍不显示，关闭后重新打开。
3. **系统设置 → 隐私与安全性 → 辅助功能：勾选 MacBar。** 移动其他应用的菜单栏图标需要模拟拖拽，这是 macOS 上唯一可行的方式。若已勾选仍提示需要授权，说明系统记录的授权与当前版本不一致：在列表中选中 MacBar 点「−」移除，再点「+」重新添加当前应用。

屏幕录制权限是可选项，仅用于截取图标缩略图。

## 架构

```
Sources/
├── MacBar/          App 装配：生命周期、状态项、面板与设置窗口
├── MacBarCore/      领域模型、布局引擎、状态机、持久化（纯 Swift，可单测）
├── MacBarSystem/    系统能力：窗口枚举、CGEvent 拖拽、辅助功能、TCC 权限
└── MacBarUI/        SwiftUI 界面：面板、设置、诊断、引导
```

`MacBarCore` 不依赖 AppKit，系统能力通过 `MacBarCore/Protocols` 中的协议注入，单元测试使用模拟实现。

## 原理与限制

macOS 没有公开 API 可以隐藏其他应用的状态项。MacBar 的做法与同类工具一致：

- 通过 `CGWindowListCopyWindowInfo` 枚举窗口层级为 25 的状态项窗口；
- 隐藏 = 用合成的鼠标事件把窗口拖到屏幕外（`x` 为负），显示 = 拖回屏幕内；
- 合成事件需要「辅助功能」权限，移动后通过轮询窗口坐标校验，失败会回滚。

因此：系统保留项（时钟、控制中心、录屏指示器等）不可隐藏；同时运行 Bartender、Ice 等同类工具会产生布局冲突，应用会提示并阻止批量操作。

## 数据与隐私

所有数据保存在 `~/Library/Application Support/MacBar/`（布局快照、偏好、设置、操作日志），应用不联网、不上传任何数据。
