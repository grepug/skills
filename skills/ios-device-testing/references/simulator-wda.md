# 模拟器：Appium 管理 WDA

默认使用维护中的 Appium XCUITest Driver 管理 WDA；它提供会话与测试 API。直接维护 WDA 生命周期只适合项目已有可用的成熟实现、明确需要底层接口，或经诊断确实需要手动接入的环境，不为省一个依赖临时重写客户端。

## 安装与隔离

先用 xcodebuildmcp CLI 发现并明确选择模拟器 UDID。读取它的技能及当前 CLI 帮助，构建并安装目标 App。不要按同名机型或“第一个 Booted”选择目标。

检查现有 Appium、XCUITest Driver 和 Node/npm；版本兼容以官方文档及包 engines/peerDependencies 为准。已有兼容环境直接复用。缺少时可在仓库外的专用目录安装固定兼容版本，使用独立 APPIUM_HOME，避免升级别人正在使用的驱动：

```sh
npm install --prefix "$ios_test_tools" "appium@$appium_version"
export APPIUM_HOME="$ios_test_state/appium-home"
"$ios_test_tools/node_modules/.bin/appium" driver install "xcuitest@$xcuitest_version"
"$ios_test_tools/node_modules/.bin/appium" driver list --installed
"$ios_test_tools/node_modules/.bin/appium" driver doctor xcuitest
```

上述路径和版本由实际环境确定，不原样使用未赋值变量。驱动已安装时跳过 install；确认 driver list、doctor 和启动日志使用的是同一个 APPIUM_HOME。若项目已有锁定依赖，优先遵循项目配置，不再创建另一套环境。

官方依据：[安装驱动](https://appium.github.io/appium-xcuitest-driver/latest/getting-started/installation/)、[兼容要求](https://appium.github.io/appium-xcuitest-driver/latest/getting-started/system-requirements/)、[Appium 要求](https://appium.io/docs/en/latest/quickstart/requirements/)。

## 启动与建立会话

先用 [多 WDA 实例排障](multiple-wda.md) 盘点。为本任务分配不与现有实例冲突的 Appium HTTP port、WDA HTTP port、MJPEG port 和 DerivedData 路径。端口可用检查只是快照，启动后必须确认实际监听；`EADDRINUSE` 时重新盘点，不杀占用者。

用当前 Appium `--help` 确认选项，绑定 loopback，把进程保留在可管理的后台任务中，记录 PID、启动时间、命令、运行目录和日志：

```sh
"$appium_bin" --address 127.0.0.1 --port "$appium_port" --log "$appium_log"
```

复用现有服务器时也检查其版本、base path、驱动、当前 session 与控制权。不要加 `--session-override`，也不启用全局宽松权限来绕过问题。新会话可能替换同一 WDA 的现有 session；同一 UDID 已有控制任务时先释放。

把 W3C new-session 请求保存到 `/tmp/ios-appium-session.json`。以下值仅为结构示例，UDID、bundle ID、端口和路径均须替换为核验后的值：

```json
{
  "capabilities": {
    "alwaysMatch": {
      "platformName": "iOS",
      "appium:automationName": "XCUITest",
      "appium:udid": "DISCOVERED-SIMULATOR-UDID",
      "appium:bundleId": "com.example.TargetApp",
      "appium:noReset": true,
      "appium:fullReset": false,
      "appium:useNewWDA": false,
      "appium:wdaLocalPort": 18200,
      "appium:mjpegServerPort": 19200,
      "appium:derivedDataPath": "/tmp/ios-task-simulator-a/DerivedData"
    }
  }
}
```

端口示例不是保留端口。模拟器与 Mac 共享端口；`wdaRemotePort` 是真机参数，不用它隔离模拟器实例。让驱动管理与其版本匹配的 WDA；不要强制借用 iPhone use 固定的真机 WDA 源码。

```sh
curl --noproxy '*' --connect-timeout 5 --max-time 180 \
  -H 'Content-Type: application/json' \
  --data-binary @/tmp/ios-appium-session.json \
  "$appium_url/session" --output /tmp/ios-appium-session-result.json
```

`appium_url` 包含服务器的实际 base path，不能猜测必有 `/wd/hub`。这是一次可能较长的启动请求，用可轮询的后台执行跟踪，等待每次不超过 60 秒，同时读取本任务日志；不要在模型工具调用中一直阻塞。保存 HTTP 状态并检查 W3C `value.error` 和 `value.sessionId`，不能只看 curl 返回码或 HTTP 200。若请求超时，先从该服务器会话和日志查明是否已经创建，禁止盲目再发 POST。

核验返回 capabilities 的目标 UDID（版本不回显时用启动日志的目标 destination 补证）、实际 WDA listener/启动日志的端口和 UDID、当前会话、source/截图及目标 App。仅 server `/status` 正常不表示 WDA 启动，更不表示目标正确。明确本任务拥有该 session 后才操作。

## 操作与验收

优先使用项目已有 Appium 客户端和测试框架。没有客户端时可在独立 Python 虚拟环境安装官方 `Appium-Python-Client`，或通过标准 Appium HTTP 接口完成有界操作。测试代码保存到 `/tmp` 文件或项目合适的测试位置。

按当前驱动文档使用 accessibility id、iOS predicate/class chain 定位，失败时读取当前 source 与截图再判断；不盲目更换标签或循环点击。截图通过 Appium/WDA 获取，坐标用设备逻辑点，不能直接使用 Mac 窗口坐标或截图像素。Appium 的手势扩展与裸 WDA API 不可混用；查当前驱动文档后调用。

用实际页面、字段或业务记录验证功能结果。结束时仅 DELETE 本任务创建的 session ID；之后只清理本任务拥有的资源，不停止复用的外部服务器。切换目标时使用下一目标的新会话、端口和日志，不复用 element ID。

## 已有直接 WDA

先核验 endpoint 的进程/启动证据与指定 UDID，并确认没有其他控制任务。需要 Appium 接入时设置 `appium:webDriverAgentUrl` 为该已核验 loopback URL，配合明确 UDID；驱动会跳过 WDA 的构建启动。保持外部 WDA 的原归属，不能认为 session 属于本任务就能停止外部 Runner。

已有成熟的直接客户端且能完成任务时可复用，不强制迁移。裸 WDA 不是完整的 Appium Server，也不承诺完整 W3C 路由；先读取该版本 API。不能为了接入检查向繁忙 WDA 创建测试 session。

官方依据：[由 Appium 管理或自行管理 WDA](https://appium.github.io/appium-xcuitest-driver/latest/guides/wda-custom-server/)、[多实例配置](https://appium.github.io/appium-xcuitest-driver/latest/guides/parallel-tests/)、[capabilities](https://appium.github.io/appium-xcuitest-driver/latest/reference/capabilities/)、[命令接口](https://appium.github.io/appium-xcuitest-driver/latest/reference/commands/)。
