# Mouser (Native)

轻量、完全本地的 Logitech 鼠标按键重映射 macOS 应用。无遥测、无云端、无 Logitech 账号依赖。

目标设备：Logitech MX Anywhere 3S(PID `0xB037`,Vendor `0x046D`,BLE 连接）。

## 下载安装

最新安装包见 [Releases](https://github.com/MIN202299/MouserNative/releases/latest)：

- `Mouser-<版本>.dmg` —— 推荐。打开后把 **Mouser** 拖进「应用程序」
- `Mouser-<版本>.zip` —— 备用。解压后把 `Mouser.app` 拖进「应用程序」

安装包为 ad-hoc 临时签名、**未做 Apple 公证**，首次打开会被 Gatekeeper 拦下，任选一种方式放行：

- 在「应用程序」里右键（或按住 Control 点击）Mouser → 「打开」→ 弹窗里再点一次「打开」；
- 或执行一次：`xattr -dr com.apple.quarantine /Applications/Mouser.app`

首次运行按引导授权「辅助功能」与「输入监控」权限，鼠标需已通过蓝牙配对。

## 功能

- **按键重映射**：中键 / 后退 / 前进 / Mode Shift 四个按键可映射为 30+ 种动作（鼠标点击、编辑快捷键、浏览器操作、系统功能、媒体控制），通过 HID++ 固件级 divert 实现，与 Logi Options+ 共存也不冲突
- **指针与滚轮**:DPI 调节（200–8000)、SmartShift 自动切换（棘轮/无极）、滚轮方向反转（写入固件）
- **电量显示**：菜单栏百分比、充放电状态、5 分钟轮询 + 设备广播实时更新
- **系统功能动作**:Mission Control、App Exposé、Launchpad、Spotlight、桌面空间左右切换、截图
- **其他**：开机自启（SMAppService)、辅助功能权限引导、Logi Options+ 冲突检测、动作失败系统通知

## 环境要求

- macOS 14.0+(针对 macOS 26 适配）；Release 安装包是 arm64 + x86_64 通用二进制，日常在 Apple Silicon 上验证
- 辅助功能权限（用于 CGEventTap 兜底路径）
- 鼠标通过蓝牙（BLE）连接

## 构建

```bash
xcodebuild -project Mouser.xcodeproj -scheme Mouser -configuration Debug build
```

签名使用 Automatic / Apple Development。链接了私有框架 SkyLight(`-F .../PrivateFrameworks -framework SkyLight`)。

## 发布新版本

推送 `v*` tag 会触发 [Release workflow](.github/workflows/release.yml)：在 macOS runner 上构建通用二进制、ad-hoc 临时签名、打成 DMG + ZIP，并自动创建对应的 GitHub Release（安装包直接挂在 Release 上供下载）。

```bash
git tag v1.0.3
git push origin v1.0.3
```

本地也可以手动打包和发布：

```bash
./script/package_release.sh           # 构建 + 打包到 dist/（DMG、ZIP、发布说明）
./script/publish_release.sh v1.0.3    # 把 dist/ 里的安装包发到 GitHub Release
```

也可以在仓库 Actions 页面手动触发 `Release` workflow（可指定 tag，或先创建草稿 Release）。

---

# 技术实现细节

## 架构总览

```
MouserApp (MenuBarExtra 菜单栏应用, LSUIElement)
 └─ AppDelegate
     ├─ DeviceManager ─── HIDPPSession ─── HIDDeviceHandle (IOKit IOHIDDevice)
     ├─ PermissionManager → ButtonInterceptor (CGEventTap)
     └─ Notifier / OptionsPlusDetector
```

| 目录 | 职责 |
|---|---|
| `HIDPP/` | HID++ 2.0 协议层：传输、会话、常量、设备管理 |
| `Engine/` | 按键拦截、动作执行、系统动作、权限 |
| `Model/` | `MouseButton` / `MouseAction` 枚举、`ConfigStore`(UserDefaults 持久化）、`DeviceState`（可观察状态） |
| `UI/` | 菜单栏视图、设置窗口（NavigationSplitView + 4 个设置页） |
| `Runtime/` | 通知、登录项、Options+ 冲突检测 |

## HID++ 协议层

### 传输（`HIDTransport.swift`)

- 所有 `IOHIDDevice` 调度在**专用 RunLoop 线程**(`HIDRunLoop`)，输入报告永不触及主线程
- 该 BLE 传输的特性：输入报告**包含** report ID 字节（回调中需剥离）；输出报告也要求 report ID 作为 buffer 首字节（与 hidapi 约定不同）
- 写报告走 `IOHIDDeviceSetReport(kIOHIDReportTypeOutput)`

### 会话（`HIDPPSession.swift`)

- 全部使用长报文（report ID `0x11`,19 字节负载）,BLE collection 只接受长输出报告
- **actor 串行化**请求：同一时间只有一个请求在飞（`acquireRequestSlot` 排队），避免响应串包
- 响应匹配：`featureIndex` + `softwareID` 相等，且 `function == 请求function` 或 `function + 1`（部分固件响应 function 会 +1)
- `featureIndex == 0xFF` 为设备错误报文；每个请求带超时（默认 2s)，超时 resume `HIDPPError.timeout`
- 非响应报文路由给 `notificationHandler`（电池广播、divert 按键事件）

### 使用的 HID++ 特性

| 特性 | ID | 用途 |
|---|---|---|
| IRoot | `0x0000` | ping 探测设备、`getFeature` 特性枚举 |
| REPROG_CONTROLS_V4 | `0x1B04` | 按键 divert / undivert |
| ADJUSTABLE_DPI | `0x2201` | DPI 读写 |
| UNIFIED_BATTERY / BATTERY_STATUS | `0x1004` / `0x1000` | 电量（优先 unified) |
| SMART_SHIFT / ENHANCED | `0x2110` / `0x2111` | SmartShift(enhanced 版 function 编号不同） |
| HIRES_WHEEL / ENHANCED | `0x2120` / `0x2121` | 滚轮模式字节（反转位） |

### 设备连接管理（`DeviceManager.swift`)

- `IOHIDManager` 按 Vendor ID `0x046D` 匹配，注册设备出现回调 + 定时重扫（3s)
- 候选设备依次 `open` + HID++ ping 探测，失败换下一个（`attemptedDevices` 去重）
- 连接后**并发** `findFeature` 枚举 8 个特性，再刷新全部状态、应用按键配置、写滚轮反转位
- 断连清理：关会话、清 `divertedCIDs` / `heldButtons`、重置 `DeviceState`、调度重扫

## 按键重映射：双路径

### 主路径 — HID++ 固件级 divert

映射的按键通过 REPROG_V4 function 3 写入 divert:

- flags `0x03`(divert + persist)。**必须带 persist 位**——仅 volatile(`0x01`）在该固件上会 ACK 但从不产生事件（真机验证）
- 未映射的按键写 `0x02` 持久 undivert，清除 Options+ 可能遗留的 divert 状态
- divert 后按键不再产生 OS 鼠标事件，按压以 HID++ 通知（function 0 或 2，两种都接受）上报，参数为按下的 CID 列表（`0x0000` 结尾）
- `heldButtons` 做边沿检测：只在"按下沿"触发动作；**断连、取消 divert、`undivertAll` 时都会清空**，避免残留状态吞掉重连后的首次按压
- 退出时 `undivertAll` 尽力清理；鼠标断电也会恢复默认

控制 ID：中键 `0x0052`、后退 `0x0053`、前进 `0x0056`、Mode Shift `0x00C4`。

### 兜底路径 — CGEventTap(`ButtonInterceptor.swift`)

设备未走 HID++（未连接/枚举失败）时，按键以普通 HID 事件到达系统：

- `.cgSessionEventTap` 监听 `otherMouseDown/Up`(Quartz 按钮号 2/3/4)
- 映射非 `.default` 的按键：down 时执行动作，down/up 都吞掉（返回 `nil`)
- tap 被系统禁用（`tapDisabledByTimeout` 等）时自动重新 enable
- 无障碍权限通过 1s 轮询跟踪，授予后自动启动 tap

### 防循环标记（`EventMarker`)

所有合成事件的 `eventSourceUserData` 写入 `"MOUT"`(`0x4D4F5554`)，拦截器遇到带标记的事件直接放行，避免吞掉自己合成的鼠标事件。

## 动作执行（`ActionPerformer.swift`)

| 动作类别 | 实现 |
|---|---|
| 键盘快捷键（复制/粘贴/浏览器等） | `CGEvent` keyDown/Up,flags 直接设在事件上，投递到 `kCGHIDEventTap` |
| 媒体键（音量/播放） | `NSEvent.otherEvent(.systemDefined, subtype: 8)`,data1 = `(nxKey << 16) \| (0xA/0xB << 8)` |
| 鼠标点击 | `CGEvent` 鼠标事件，位置取当前光标 |
| Mission Control / Launchpad / Spotlight / 截图 | `NSWorkspace.openApplication` 打开对应系统组件 |

浏览器前进/后退用 `Cmd+[`(`0x21`)/ `Cmd+]`(`0x1E`)——不用 `Cmd+方向键`，后者在焦点位于文本框时会被解释成行首/行尾。

## 系统动作：桌面切换与 App Exposé(`SystemActions.swift`)

普通合成按键发到 HID tap 会被 WindowServer 的符号热键处理器忽略，因此这两个动作用私有 API（与 yabai、Python 版 Mouser 相同）:

- **桌面左/右切换**:`CGSGetSymbolicHotKeyValue`(hotkey ID 79/81）读取系统当前配置的按键绑定（跟随用户自定义），keyDown/Up 带上修饰键 flags 投递到 **`kCGSessionEventTap`**（关键：HID tap 会被忽略）。若该热键在系统设置中被禁用，临时 `CGSSetSymbolicHotKeyEnabled` 启用、发事件、`usleep(50ms)` 等 WindowServer 处理后恢复原状
- **App Exposé**:`CoreDockSendNotification("com.apple.expose.front.awake")` 直接通知 Dock，无 UI 副作用（早期方案用 `AXShowMenu` 弹 Dock 右键菜单再找"显示所有窗口"，会产生菜单闪烁）

私有符号通过 `@_silgen_name` 声明，由链接的 SkyLight 框架提供。

## 配置与状态

- `ConfigStore`:`UserDefaults` 持久化，按键映射存为 `[String: String]` JSON(button rawValue → action rawValue);`@Observable` 供 SwiftUI 直接绑定，修改即保存并即时下发 HID++ 配置
- `DeviceState`：连接状态、设备名、电量、DPI、SmartShift、滚轮模式字节的单一可观察快照

## UI

- **菜单栏**:`MenuBarExtra`，图标 + 可选电量百分比；设置窗口打开时通过 `AppActivationPolicy`（引用计数）把 `.accessory` 切为 `.regular` 显示 Dock 图标，关窗还原
- **设置窗口**:NavigationSplitView(200pt 侧栏 + 前进/后退历史）,4 个页面：
  - Buttons：可点击的鼠标示意图热点 + popover 选择器，按分类分组的动作菜单
  - Pointer & Scroll:DPI 滑杆、SmartShift 开关与灵敏度、滚轮反转
  - Battery：大图标电量、菜单栏百分比开关、手动刷新
- 滚轮反转是 0x2121 模式字节的**读-改-写**：只动 invert 位（bit 2)，保留 target/hi-res 位

## 其他

- **电量**：连接时读一次，之后 300s 轮询 + 接收设备广播（function 0 且 softwareID 非本机）
- **Options+ 冲突检测**：启动时扫描运行中的应用（`com.logi.*options*`)，发现即通知
- **登录项**:`SMAppService.mainApp` 注册/注销
- **本地化**:`Localizable.xcstrings`（中/英）
