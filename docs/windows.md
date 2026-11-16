# Windows 构建与使用指南

本文说明如何在本机 Windows 上编译、打包并运行 HGhub 桌面客户端（Tauri 2 + React）。
仓库里的平台相关代码原本就区分了 Windows（自绘标题栏、边缘缩放、`http://hg.localhost`
媒体协议、读取注册表系统代理），本指南配套的改动主要解决 **Windows 打包配置、脚本与
构建流程**，功能与安全策略保持不变。

适用版本：`1.2.1`（以 `src-tauri/tauri.conf.json` 的 `version` 为准）。

---

## 1. 最快上手

在 PowerShell 中执行（不要用 CMD 的 `>` 重定向写脚本）：

```powershell
git clone https://github.com/AIRzZ90/study-materials-fork.git
cd study-materials-fork
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\build.ps1
```

或者直接双击仓库根目录的 `build-windows.bat`（等价于第二条命令）。

产物在 `dist-windows\`：

| 文件 | 说明 |
| --- | --- |
| `HGhub_1.2.1_x64-setup.exe` | NSIS 安装包（当前用户安装，无需管理员） |
| `HGhub_1.2.1_x64_portable.zip` | 便携版，解压后直接运行 `HGhub.exe` |

> 首次构建需要联网下载 Rust crate、NSIS 以及 WebView2 引导程序，通常 5–15 分钟；
> 之后的增量构建会快很多。构建缓存位于 `src-tauri\target\`，可能占用数 GB。

---

## 2. 本仓库针对 Windows 做了哪些改动

| 位置 | 改动 | 原因 |
| --- | --- | --- |
| `src-tauri/tauri.conf.json` | `bundle.targets` 由写死的 `["nsis","deb","appimage"]` 改为 `"all"` | 原配置在非 Linux 平台会为 `deb`/`appimage` 打印 `ignoring ...` 告警；`"all"` 表示“当前平台支持的全部格式”，再由平台配置决定具体格式 |
| `src-tauri/tauri.windows.conf.json` | 新增，Tauri 在 Windows 上会自动合并 | 只打 NSIS；当前用户安装（免管理员）；简体/繁体中文与英文安装界面；内嵌 WebView2 引导程序 |
| `package.json` | 固定 `packageManager: pnpm@10.34.9` | `corepack` 可据此自动选择 pnpm 版本 |
| `package.json` | 新增 `typecheck`、`win:dev`、`win:build`、`win:build:exe` | 纯 Windows 场景的快捷命令 |
| `scripts/windows/check.ps1` | 新增 | 一次性检查 Node / pnpm / Rust / MSVC / WebView2 |
| `scripts/windows/build.ps1` | 新增 | 一键安装依赖、构建、收集安装包与便携 zip |
| `scripts/windows/dev.ps1` | 新增 | 开发模式启动 |
| `build-windows.bat` | 新增 | 双击即可构建 |
| `.github/workflows/build-windows.yml` | 新增 | 在 `windows-latest` 上手动/打标签构建 |
| `.gitattributes` | 为 `*.ps1` / `*.bat` / `*.cmd` 指定 CRLF | 避免 Windows 检出后批处理解析异常 |
| `.gitignore` | 忽略 `dist-windows/` | 本地产物不入库 |

界面层无需改动：`src/api.ts` 会按 User-Agent 识别 `windows`，桌面外壳使用
`.plat-windows` 样式，媒体地址在 Windows 上是 `http://hg.localhost`（Rust 侧
`src-tauri/src/media.rs` 的 `LOCAL_ORIGIN` 与之一致）。

---

## 3. 环境要求

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| Windows | 10 1809+ / 11，x64 | WebView2 依赖；ARM64 未验证 |
| Node.js | 22 LTS（≥ 20 可编译） | 只用于前端构建 |
| pnpm | 10.x | 仓库已固定 10.34.9 |
| Rust | 1.90+，`stable-x86_64-pc-windows-msvc` | 必须用 MSVC 工具链，不能是 GNU |
| Visual Studio 2022 生成工具 | “使用 C++ 的桌面开发” 工作负载 + Windows 10/11 SDK | 提供 `link.exe`，Rust 链接必需 |
| WebView2 Runtime | Evergreen | Windows 11 自带；Windows 10 通常随 Edge 安装 |
| 磁盘 | 建议 10 GB 空闲 | 依赖 + Rust target + 安装包 |

### 3.1 安装命令

以**管理员** PowerShell 执行（`corepack enable` 需要写 Node 安装目录）：

```powershell
winget install --id OpenJS.NodeJS.LTS -e
winget install --id Rustlang.Rustup -e
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

# 新开一个 PowerShell 窗口后
corepack enable
rustup default stable-msvc
```

如果 `corepack enable` 报 `EPERM`，改用：

```powershell
npm install -g pnpm@10
```

Visual Studio 生成工具安装包约 1–2 GB，安装完成后**必须重开终端**，否则 `link.exe`
不在环境里。`check.ps1` 会通过 `vswhere.exe` 检测 C++ 工具链，比只看 PATH 可靠。

### 3.2 自检

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\check.ps1
```

全部显示 `[ OK ]`、退出码为 0 即可构建。缺项会打印可直接复制的修复命令。

---

## 4. 构建

### 4.1 一键脚本

```powershell
# 默认：NSIS 安装包 + 便携 zip
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\build.ps1

# 只构建、不重新装依赖（node_modules 已是最新时）
scripts\windows\build.ps1 -SkipInstall

# 清掉 Rust 缓存后重建（换工具链 / 链接错误时用）
scripts\windows\build.ps1 -Clean

# 额外/改用 MSI（需要联网让 Tauri 自动下载 WiX）
scripts\windows\build.ps1 -Bundle msi

# 只要安装包，不生成便携 zip
scripts\windows\build.ps1 -NoPortable

# 只要便携 exe（不生成安装包）
pnpm win:build:exe
```

参数说明：

| 参数 | 默认 | 作用 |
| --- | --- | --- |
| `-Bundle` | `nsis` | 安装包格式：`nsis` / `msi` |
| `-SkipInstall` | 关 | 跳过 `pnpm install --frozen-lockfile` |
| `-Clean` | 关 | 先执行 `cargo clean` |
| `-NoPortable` | 关 | 不生成便携 zip |
| `-OutDir` | `dist-windows` | 产物目录（相对仓库根） |

### 4.2 手动命令（与脚本等价）

```powershell
pnpm install --frozen-lockfile
pnpm tauri build --bundles nsis
```

`pnpm app:build` 也可以，它会读取 `tauri.windows.conf.json`，在 Windows 上等价于
NSIS 构建。便携 exe 用：

```powershell
pnpm win:build:exe   # 等价于 tauri build --no-bundle，只出 exe，不打包
```

构建产物路径：

```text
src-tauri/target/release/bundle/nsis/HGhub_1.2.1_x64-setup.exe
src-tauri/target/release/huangguo-client.exe     # 主程序（Tauri 打包时会重命名为 HGhub.exe）
```

### 4.3 安装包行为

`src-tauri/tauri.windows.conf.json` 中的关键设置：

```json
{
  "bundle": {
    "targets": ["nsis"],
    "windows": {
      "webviewInstallMode": { "type": "embedBootstrapper", "silent": true },
      "nsis": {
        "installMode": "currentUser",
        "languages": ["SimpChinese", "TradChinese", "English"],
        "displayLanguageSelector": false
      }
    }
  }
}
```

- **当前用户安装**：装到 `%LOCALAPPDATA%\HGhub`，不弹 UAC，卸载在「设置 → 应用」里。
  如需装到 `Program Files`，把 `installMode` 改成 `"perMachine"`（会要求管理员权限）。
- **WebView2**：内嵌 `MicrosoftEdgeWebview2Setup.exe` 引导程序（约 1.8 MB），首次安装时若
  系统没有 WebView2 会自动下载安装。完全离线分发可改为
  `{ "type": "offlineInstaller", "silent": true }`（安装包会增大约 120 MB）。
- **语言**：按系统语言自动选择，中文系统显示简体中文界面。
- **图标**：使用 `src-tauri/icons/icon.ico`。

---

## 5. 开发与调试

```powershell
# 桌面应用（Vite + Rust，热重载）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\dev.ps1
# 或
pnpm app:dev

# 只跑前端页面（浏览器打开 http://localhost:1420；没有 Tauri API，业务接口不可用）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\dev.ps1 -Web
```

- 前端改动即时 HMR；Rust 改动会触发重新编译并重启窗口。
- 开发模式会显示控制台窗口（`windows_subsystem = "windows"` 只对 release 生效），
  这是刻意保留的，方便看 panic 与日志。
- 端口固定 `1420`（`vite.config.ts` 的 `strictPort: true`），被占用时先释放：

```powershell
netstat -ano | findstr :1420
taskkill /PID <PID> /F
```

- 运行期错误会写入应用数据目录的 `debug.log`；播放问题可在「设置 → 播放诊断日志」
  打开诊断后复现，再复制日志。

---

## 6. 数据目录与卸载残留

| 内容 | 路径 |
| --- | --- |
| 会话 / 线路 / 安全设置 / 日志 | `%APPDATA%\com.hghub.huangguo\` |
| 具体文件 | `session.json`、`line.json`、`security.json`、`debug.log`、`playback.log`、`playback-diagnostics.json` |
| 程序（NSIS 当前用户安装） | `%LOCALAPPDATA%\HGhub\` |
| WebView2 缓存 | 由系统管理，可用「设置 → 清理缓存」清媒体缓存 |

卸载程序不会删除 `%APPDATA%\com.hghub.huangguo`；需要彻底清空时手动删除该目录。

---

## 7. 网络与代理

客户端的所有上游请求由 Rust `reqwest` 发出，**不共享浏览器的代理与证书库**：

- 勾选「使用系统代理」的 Clash/v2ray 等，会写入
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings` 的
  `ProxyEnable` / `ProxyServer`；`reqwest` 开启了 `system-proxy`，能读到固定代理。
- **PAC（`AutoConfigURL`）不支持**，只认固定代理。需要 PAC 时改用 TUN/虚拟网卡模式，
  或设置环境变量 `HGHUB_PROXY`。
- 临时指定代理：

```powershell
$env:HGHUB_PROXY = "http://127.0.0.1:7897"
.\HGhub.exe
```

- 公司网络做 TLS 中间人（自签根证书）时，`rustls` 不会读取 Windows 证书store，
  需要在代码中显式添加根证书或关闭严格校验（不推荐）。
- 应用内「设置 → 网络诊断」会输出 DNS / 代理环境快照，反馈问题时一并附上
  `debug.log`。

---

## 8. 常见问题

### 8.1 构建日志出现 `ignoring deb` / `ignoring appimage`

Tauri 会忽略当前平台不支持的打包目标（只告警，不影响 NSIS 产物）。本项目已在
`tauri.windows.conf.json` 中把 Windows 限定为 `["nsis"]`，正常不会再出现。若你改过配置，
构建时显式指定即可：

```powershell
pnpm tauri build --bundles nsis
```

注意不要反着来：在 Windows 上传 `--bundles deb` 这类当前平台不支持的格式，会没有可用产物。

### 8.2 `error: linker 'link.exe' not found` / `LNK1104`

没有安装 MSVC 链接器：

1. 安装 Visual Studio 2022 生成工具，勾选「使用 C++ 的桌面开发」；
2. 确认 `rustup default stable-msvc`（不是 `stable-gnu`）；
3. 重开终端后再试；仍失败可运行 `scripts\windows\check.ps1` 查看检测结果。

### 8.3 安装后启动白屏 / 提示缺少 WebView2

安装 [WebView2 Evergreen Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)，
或把 `tauri.windows.conf.json` 的 `webviewInstallMode` 改成 `offlineInstaller` 后重新打包。

### 8.4 SmartScreen「Windows 已保护你的电脑」

安装包未做代码签名。选择「更多信息 → 仍要运行」即可；正式分发建议购买代码签名证书，
见第 10 节。

### 8.5 杀毒软件拦截构建或运行

把仓库目录和 `src-tauri\target` 加入杀软排除项，可显著提升构建速度并避免
`cargo build` 被杀软锁文件导致的随机失败。

### 8.6 路径过长（260 字符限制）

Rust 的 `target` 与 pnpm 的 `node_modules` 层级较深：

```powershell
# 管理员 PowerShell
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f
git config --global core.longpaths true
```

同时尽量把仓库放在 `D:\dev\...` 这类短路径，不要放在 OneDrive/中文深层目录。

### 8.7 放在 exFAT U 盘 / 移动硬盘上构建失败

pnpm 已配置 `node-linker=hoisted` 以兼容不支持符号链接的文件系统，但 Rust 的
`target` 仍可能出问题。建议在 NTFS 本地盘构建。

### 8.8 `pnpm install` 提示有依赖的构建脚本被忽略

仓库已在 `package.json` 与 `pnpm-workspace.yaml` 允许 `esbuild`。若仍提示
`Ignored build scripts`，执行 `pnpm approve-builds` 并勾选 `esbuild`。

### 8.9 Rust / crate 下载慢或超时

使用镜像（任选其一），写入 `%USERPROFILE%\.cargo\config.toml`：

```toml
[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[net]
git-fetch-with-cli = true
```

并设置 rustup 镜像环境变量后重装工具链：

```powershell
$env:RUSTUP_DIST_SERVER = "https://rsproxy.cn"
$env:RUSTUP_UPDATE_ROOT = "https://rsproxy.cn/rustup"
```

前端依赖可临时切 npm 镜像：`pnpm config set registry https://registry.npmmirror.com`。

### 8.10 构建成功但接口全部失败

先在「设置 → 网络诊断」查看代理/DNS；若浏览器能打开官网而客户端不行，多半是代理
模式问题（PAC 不支持），改用 TUN 或设置 `HGHUB_PROXY`。日志在
`%APPDATA%\com.hghub.huangguo\debug.log`。

### 8.11 双击标题栏无法最大化

窗口是无边框自绘标题栏。若遇到双击无效，请先确认没有在拖动中松开；必要时用标题栏
右侧的「最大化」按钮。此类交互问题与显示器缩放/多屏 DPI 有关，可在 Issue 中附上
系统版本与缩放比例。

---

## 9. 完全手动构建（不使用脚本）

```powershell
# 1. 环境
node -v            # v22.x
pnpm -v            # 10.x
rustc -V           # 1.90+ msvc

# 2. 依赖
pnpm install --frozen-lockfile

# 3. 类型检查 + 前端产物（可选，tauri build 会自动跑）
pnpm typecheck
pnpm build

# 4. 桌面安装包
pnpm tauri build --bundles nsis

# 5. 便携 exe
pnpm tauri build --no-bundle
Copy-Item src-tauri\target\release\huangguo-client.exe .\HGhub.exe

# 6. 清理
cargo clean --manifest-path src-tauri\Cargo.toml
```

---

## 10. 代码签名（可选，正式分发建议）

未签名 exe 的 SmartScreen 提示无法通过配置消除，只能签名并积累信誉。准备
Authenticode 证书后，在 `src-tauri/tauri.windows.conf.json` 的 `bundle.windows` 中配置：

```json
{
  "bundle": {
    "windows": {
      "certificateThumbprint": "A1B2C3...",
      "digestAlgorithm": "sha256",
      "timestampUrl": "http://timestamp.digicert.com"
    }
  }
}
```

或使用自定义签名命令：

```json
{
  "bundle": {
    "windows": {
      "signCommand": {
        "cmd": "signtool",
        "args": ["sign", "/fd", "sha256", "/tr", "http://timestamp.digicert.com", "/td", "sha256", "/a", "%1"]
      }
    }
  }
}
```

证书放进当前用户证书库并保证私钥可访问；CI 中不要把 `.pfx` 提交进仓库，用 Secret
注入并通过 `signCommand` 调用。

---

## 11. 通过 GitHub Actions 构建

两种方式，均无需本地 Windows 环境：

1. **只出产物**：Actions → `Build Windows` → Run workflow（可选 `nsis` / `msi`），
   构建完成后下载 `HGhub-windows-nsis` 工件。
2. **发 Release**：推送 `v*` 标签，`release.yml` 会同时构建 Windows / Android / macOS
   并发布。Windows 任务使用 `windows-latest`，产物为 NSIS 安装包与便携 zip。

---

## 12. 已知限制

- 本适配在 Linux 上完成静态检查（前端 `pnpm build` 通过、Tauri 配置符合 v2 schema），
  **最终 exe 需在 Windows 或 GitHub Actions 上编译验证**；首次构建若报错，请附
  `scripts\windows\check.ps1` 输出与完整构建日志。
- Windows ARM64 未验证；如使用骁龙本，请安装 arm64 版 Node/Rust 并自行测试。
- 当前不内置自动更新，更新通过 GitHub Release 手动下载。
- 未启用单实例：重复启动会打开多个窗口。
- 播放依赖上游接口可用性，与平台无关；接口变更时客户端会提示加载失败。
