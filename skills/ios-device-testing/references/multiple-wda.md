# 同一 Mac 的多个 WDA 实例

## 先盘点，后操作

出现多个端口、多个运行目录、连接到错误设备、端口占用、session 不断失效或配置与实际画面不符时，先建立映射表：

| 字段 | 证据 |
| --- | --- |
| 目标类型与 UDID | xcodebuildmcp CLI 的设备/模拟器发现结果与用户目标 |
| 控制方 | 当前任务记录、其他任务记录或用户确认；进程属于当前用户不等于属于当前任务 |
| iPhone use Runtime | 实际工具绑定的 state directory、base URL、config、job；不是任意找到的一份 config |
| Appium 实例 | HTTP URL/base path、PID/启动时间、APPIUM_HOME、日志、会话与 capabilities |
| WDA HTTP | 实际 listener PID、进程命令、启动日志、端口 |
| 真机 USB 转发 | 进程与父进程、指定 UDID、本机 local port、设备 device port |
| Runner | 启动命令/日志的 destination UDID、构建目录及当前存活进程 |
| 会话 | endpoint 对应的 session ID、创建者、最后结果；不能只凭持久化缓存认定仍有效 |
| 屏幕流 | MJPEG port 和控制方；它与 WDA HTTP、Appium HTTP 是不同端口 |

运行附带的只读脚本，`skill_root` 为本技能的实际目录：

```sh
python3 "$skill_root/scripts/wda_inventory.py" \
  --state-dir "$iphone_use_state" \
  --endpoint http://127.0.0.1:18100 \
  --endpoint http://127.0.0.1:18200 \
  --output /tmp/ios-wda-inventory.json
```

端口须替换为发现的候选；不要扫描整个端口范围。脚本默认只读取现有 iPhone use 新旧标准运行目录，也可重复传指定目录。仅显式提供的 endpoint 会 GET `/status`；不创建会话、不发送点击、不启动服务、不发信号。为旧 Appium base path 可传 `http://127.0.0.1:4723/wd/hub`。最多探测 8 个 endpoint，每个超时 2 秒。

输出是观察证据，**不会认证任务归属或 UDID 绑定**。检查 `collection_errors`、state errors、状态截断和相关进程；采集失败不是“没有实例”。lsof 返回本用户可见监听，不保证有权限看见所有进程。配置冲突提示只代表声明冲突，不代表实际服务对应哪个设备。退出码 0 表示采集完成，2 表示已有报告但存在缺项/探测错误，1 表示报告写入失败；这些都不是设备 READY 结论。输出文件权限为 600，拒绝覆盖已有文件，重复盘点使用新的任务文件名。

真实设备身份需要从活的转发/Runner 命令或精确对应的启动日志取证；Appium 需关联 session capabilities、Runner destination 与端口日志。WDA `/status` 的机型、系统和名称只能补充，不能区分两台相同设备。进程命令省略 UDID 时，继续查启动链和日志；仍无唯一对应就不要操作、不要重启该 endpoint，报告缺少的证据。

## 冲突分类

| 现象 | 判断与处理 |
| --- | --- |
| 多个健康端口连接不同 UDID | 正常共存。绑定目标 endpoint，保留其他实例 |
| 默认端口已被另一目标占用 | 不能因健康而复用；为本任务选空闲端口和独立目录，重新验证启动后的映射 |
| config 的 UDID 与活的转发/Runner 不一致 | 停止本任务的设备动作。保留不明进程，查错误 Runtime/旧转发/旧配置；不能直接覆盖共享配置 |
| 同一个 UDID 被多个控制方使用 | 即使端口不同也冲突。等现有控制方释放或请用户协调，不另建 Runtime/会话绕开锁 |
| 端口可达、READY/树/前台失败 | 区分锁屏、App 认证、XCTest 通道、失效 session 和错误 endpoint；健康状态不等于可操作 |
| `device_busy` | 尊重相同 Runtime 的共享锁，等当前操作结束；不删除锁文件、不换目录重试 |
| Appium 正常但 WDA 未就绪 | 查该 session 的驱动/Xcode 日志、版本兼容与实际 WDA port，不循环创建新 session |
| WDA HTTP 健康，MJPEG 空白/冲突 | 单独排查预览与 MJPEG port，不重启健康控制通道 |
| 启动 job 长期 running | Runner 可以长期运行；看服务与阶段，不能等待 succeeded 或反复 start |
| 持久化 session/job 有记录，活进程不存在 | 记录陈旧。重新发现并按当前任务归属恢复，不仅按旧 PID 发信号 |

## 有界修复

先读取当前工具的准确错误与日志，按证据选择恢复层，不规定每个故障一律重建：

1. 目标或 Runtime 错误：改本任务的绑定；若会影响已有共享配置先协调，优先使用任务独立配置。
2. 失效 session：确认本任务控制权后重建自己的会话，不删除其他 session；先核对可能已经生效的动作。
3. 转发或 Runner 故障：仅重启本任务拥有的资源。信号前重新核验 PID、启动时间、命令、父/进程组、目标 UDID、端口和任务/job 记录，防止 PID 复用。iPhone use stop 必须带精确 job_id，不用无 ID 的批量 stop。
4. 缺少/失效构建：按实际诊断重建自己的产物；不清理全局 DerivedData，不升级共享驱动，不删除旧 WDA 源码。
5. 服务恢复后重新核验目标映射、通道及 App 当前状态，继续剩余步骤，不能重放整段任务。

同一故障首次恢复后无新证据仍失败时，停止重复重启，转向准确日志与缺项；插件冷却、活动 job 和用户禁止重启的限制始终保留。无法安全修复时记录已验证层、具体阻塞与下一步。若需要停止其他控制方或降级 computer use，给出具体影响和推荐方案，等待实际答复；其余独立工作继续。
