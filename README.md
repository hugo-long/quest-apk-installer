# Quest APK Installer

一个简单的 Windows 桌面工具：选择存放 APK 的文件夹，通过 ADB 将应用逐个安装到 Quest。

独立社区项目，与 Meta、Google 无隶属或官方合作关系。不附带 ADB、驱动、游戏或其他 APK。

## 下载与启动

前往本仓库的 **Releases** 页面，下载 `QuestApkInstaller-v0.1.0-Windows.zip`，完整解压后双击 `QuestApkInstaller.exe`。

请保留 EXE 与 `QuestApkInstaller.ps1` 在同一目录。GitHub 自动生成的 Source code 压缩包只有源码，需自行构建。

目标环境为 Windows 10/11，使用系统内的 Windows PowerShell 5.1 和 .NET Framework。无需安装 Python、Unity 或完整 Android Studio。本版尚未完成所有系统版本、缩放比例和设备组合的兼容性测试。

## 使用步骤

1. Quest 开启开发者模式，用支持数据传输的 USB 线连接电脑，在头显内允许 USB 调试。
2. 准备 [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools)。工具会查找 PATH、同目录 `platform-tools` 文件夹和常规 Android SDK 中的 ADB；也可以点击“选择 ADB”手动选择 `adb.exe`。不要把它与所属目录里的 DLL 分开。
3. 点击“刷新设备”，核对目标设备序列号。如果连接了其他 Android 设备，也可能出现在列表中。
4. 点击“选择文件夹”，选择 APK 目录。只扫描当前目录，不包含子目录。
5. 点击“开始安装”，查看每项的状态和日志。可重试失败或未执行的项目，并导出日志。

没有设备也可以点击“预览演示”。演示使用六个虚构文件，其中一个模拟安装失败，不会向设备写入数据。

## 功能与原理

- 顺序安装当前目录中的独立 APK。
- 显示已处理数量、成功/失败状态及 ADB 返回信息。
- 重试失败/未执行项目。
- 完成当前安装后停止后续队列。
- 导出本地文本日志。

每个真实任务执行 `adb -s <serial> install -r <apk>`。`-r` 尝试保留已有应用数据进行覆盖安装，仍需满足签名、版本和兼容性要求。

## 当前限制

- 不支持拆分 APK、APKS、XAPK、OBB 数据包或自动降级。
- 不强制卸载已有应用，不回滚已完成的安装。
- 安装过程中关闭窗口会先等待当前任务结束；尚未实现安装超时或强制取消。
- 设备检测可能等待最多约 8 秒；安装任务在后台进程中运行。
- 安装成功不代表应用支持 Quest 或 VR 模式。
- 未进行代码签名，系统可能显示未知发布者提示；请核对下载来源和校验值，不要关闭安全软件。

## 隐私与反馈

程序没有内置遥测、账户系统或日志自动上传功能。设备查询及安装由本机 ADB 执行。

日志可能包含本机文件路径、设备序列号和 APK 文件名。提交 Issue 前请手动删去这些信息。请提供 Windows 版本、头显型号、复现步骤及脱敏后的错误信息，不要上传商业 APK 或个人凭据。

## 从源码构建

在 **Windows PowerShell 5.1** 中进入项目目录，执行：

```powershell
.\build.ps1
```

脚本使用 Windows 自带的 .NET Framework C# 编译器，输出到 `dist/`，并创建 Windows 发布 ZIP 和 SHA-256 校验文件。构建不下载或打包 ADB。

可选自检（需已安装 ADB；只查询设备，不安装 APK）：

```powershell
powershell.exe -NoProfile -STA -File .\QuestApkInstaller.ps1 -SelfTest
```

自检覆盖窗口构建、ADB 查询、Unicode 文件名、模拟成功/失败队列及停止逻辑。已有用户反馈实际安装可用，但这些检查不等同于跨设备兼容性认证。

## 许可证

项目源码采用 [MIT License](LICENSE)，允许使用、修改、分发和商用，须保留版权与许可声明。外部 ADB、系统运行环境及驱动遵循各自许可，本项目的 MIT 许可不覆盖这些组件。

请只安装你有权使用的应用。本项目不提供付费验证绕过或破解功能。
