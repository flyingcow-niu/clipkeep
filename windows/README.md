# ClipKeep for Windows — early preview

Windows 11 原生 WPF 剪贴板工具，使用 C# / .NET 10。当前是从零实现的首个预览版，未宣称与 macOS 完全一致。

## 编译

在 Windows 上安装 .NET 10 SDK 和 PowerShell 7，不需要 Visual Studio。若用 Visual Studio，需要支持 .NET 10 的版本及桌面开发工作负载。

```powershell
cd windows
pwsh ./test.ps1
pwsh ./build.ps1 -Runtime win-x64
```

输出：`windows/dist/win-x64/ClipKeep.exe`。发布产物包含 .NET 运行时，**分发时必须复制整个目录**，不要只复制 EXE。CI 将目录打包为 ZIP；没有安装程序和自动更新。`win-arm64` 可作为编译目标，但尚无 ARM64 原生运行验收。

在 macOS/Linux 上可运行平台独立规则测试，也可恢复 Windows 目标引用包检查编译；不能运行 WPF、DPAPI 或验证 Windows 桌面交互：

```sh
cd windows
dotnet run --project ClipKeep.Core.Tests -c Release
dotnet build ClipKeep.Windows/ClipKeep.Windows.csproj -c Release
```

## 使用

- 启动后在系统托盘驻留，Ctrl+Shift+V 打开面板；快捷键被占用时使用托盘菜单。
- 文本（含 HTML/RTF）、图片、文件引用历史；支持搜索、收藏、保留期限、条数限制、暂停记录和按进程排除。
- 左右选择，Ctrl+C 复制并收起，Enter 粘贴，Shift+Enter 纯文本，Ctrl+D 收藏，Ctrl+Delete 删除。
- 完整可见卡片角落常驻 Ctrl+数字，按对应组合直接粘贴。搜索框选中文字时 Ctrl+C 保留普通文字复制。
- 自动粘贴受 Windows 权限隔离影响；普通权限程序可能无法向管理员窗口投递按键。失败时内容保留在剪贴板，可手动 Ctrl+V。

## 数据和隐私

数据保存在 `%LOCALAPPDATA%\ClipKeep\history.dat`，整个快照通过当前 Windows 用户 DPAPI 加密，包括设置和元数据。换账户、重装系统或迁移到另一台电脑后可能无法解密；目前不提供可移植备份恢复。

敏感格式标记和排除进程为尽力保护。默认排除 1Password、Bitwarden、KeePass 和 KeePassXC；设置中输入不带 `.exe` 的进程名。存在任一 Windows 剪贴板历史／云同步 opt-out 格式时保守跳过。不要假设所有密码都会自动被识别。

单条载荷上限 8 MiB；总载荷上限 64 MiB（即使条数和天数设为 0 也存在）；超出总量时清理最旧的非收藏，收藏不会自动删除。默认保存 30 天、最多 500 条非收藏。文件记录仅保存路径，不复制或备份原文件。

## 尚未完成

- 自动缩写展开、中文输入法适配、手动短语编辑；macOS 的缩写功能尚未移植。
- 自定义全局快捷键、面板关闭时数字快选、登录自动启动。
- 多屏精确定位、跨应用完整验收、长期性能测试。
- Windows 代码签名、安装器、升级迁移及备份恢复。

所有平台验收状态见 [平台状态](../docs/PLATFORM_STATUS.md)。编译通过和窗口构造测试通过不代表真实桌面操作已经全部验证。
