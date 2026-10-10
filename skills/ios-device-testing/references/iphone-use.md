# 真机：设置与使用 iPhone use

源仓库：[zhongerxin/iPhone-use](https://github.com/zhongerxin/iPhone-use)。安装和操作以实际安装版本的 README、`iphone-use-setup`、`iphone-use` 技能及工具 schema 为准，不把某个用户的插件 cache 路径写成固定依赖。

## 缺少插件或工具

1. 检查实际可调用的工具绑定，寻找 `pua_setup`、`pua_ready` 与所需动作；安装记录或工具清单不证明当前聊天已加载绑定。
2. 已安装时定位当前插件根目录，读取它的技能和安装状态，避免重复注册 MCP。缺少时检查 Codex CLI、Python 3、Node/npm、完整 Xcode 和 USB 设备；版本要求从上游 README 与安装脚本读取。
3. 在合适的本机目录获取仓库，读取 README 和 `scripts/install.sh` 后运行官方安装入口。保留已有 checkout 和本地改动，不覆盖或为了升级重置源码。记录实际 commit/插件版本。

```sh
git clone https://github.com/zhongerxin/iPhone-use.git "$iphone_use_checkout"
cd "$iphone_use_checkout"
sh scripts/install.sh
```

变量由 agent 根据已发现的目录设置，路径须正确引用。官方脚本会注册插件及 MCP；不要再手动注册一套同名服务。若当前聊天尚未加载新工具，明确说明需要重连，然后从保存的目标记录继续。已有插件代码可用时，先评估下述代码入口能否继续当前任务。

## 复用配置，补齐实际缺项

先读 `iphone-use-setup`，本对话首次使用调用 `pua_setup(action="status")`。核对配置的 UDID、endpoint、local/device port 与实际绑定证据；配置指向别的目标时不能直接覆盖。单一 Runtime 不能在每次动作上传任意 UDID；先确定本次工具绑定实际使用的运行目录和 URL。

- 有健康服务：先确认目标及控制权，再调用 READY。
- 对应 start/recover job 已 queued/running：记录 job ID，查询同一个工作；不要重复启动。`status` 返回 `jobs` 数组，按 ID 取项。
- 已配置、没有对应活动工作且服务未启动：调用一次 start，复用构建。
- 未配置：discover 设备，确认自己的 Team ID 与可签名 bundle ID。按实际 schema 使用 fetch/configure/build/start；首次配置可设置 source_dir、local_port、device_port。
- 仅在明确缺失源码时 fetch；构建缺失、签名过期或二进制不兼容时才 build。冷启动不等于整套重装。

fetch/build/start 可能返回后台 job。沿其状态、日志和建议间隔做有界等待，不能将超时解释为应该再次 start。长期运行的 Runner 在服务可用后即可验 READY，不必等 job succeeded。正常初始化不要因“服务尚未启动”提前结束。

Xcode 登录、设备信任、开发者模式、开发签名信任或解锁由用户本人完成。若 Personal Team 容量/签名限制阻塞，报告准确缺项；不得删除用户 App、吊销共享证书或自动改用付费账户。

## READY 与操作

完成目标绑定后，先确定恢复权限，再显式传入 recover：本任务拥有且允许恢复的服务调用 `pua_ready(recover=true, screenshot=false)`；复用外部或以前任务的服务、归属未确认、明确只读或禁止重启时调用 `pua_ready(recover=false, screenshot=false)`。不能省略 recover 而意外启用默认自动恢复。复用返回的 observation，不立即再读一次相同页面。

必须收到 `ready=true, state="ready"` 才进行手机动作。`recovering`/`recovery_required` 不是成功；查询对应 recovery job，达到可服务阶段后重新 READY。进程、端口、Runner 图标、预览画面和 build 成功都不替代通道验收。

当前版本 READY 检查会话、前台、树、视口与锁屏等，**不能单凭配置 UDID 或预览机型标题断言 endpoint 的实际设备身份**。多个实例时按 [多 WDA 实例排障](multiple-wda.md) 取证。

实际动作交给 `iphone-use` 技能：优先语义定位；未知页面在下一步需要时观察；异常先看当前截图；截图坐标按工具提供的比例换算为 iPhone 点。最终功能结果显式验收。认证接管与业务动作不确定时沿用其保护，不因更换调用入口而重复输入或提交。

## 多 Runtime 与代码入口

隔离不同设备可使用不同 `IPHONE_USE_STATE_DIR`/`--state-dir` 和 `WDA_URL`/`--url`，但每个 Runtime 的配置、会话和锁必须一致；不能为避开 `device_busy` 为同一设备新建目录。保留现有默认配置，额外目标优先独立运行目录。安装版本是否支持这些参数先检查实际源码或帮助。

MCP 绑定不可用或该绑定指向其他目标时，可用本技能的文件入口，调用**已安装插件的原始 Runtime**，保留它的会话、锁、错误和恢复机制：

```sh
python3 "$skill_root/scripts/iphone_use_call.py" \
  --plugin-root "$iphone_use_root" \
  --state-dir "$iphone_use_state" --url "$wda_url" \
  --arguments-file /tmp/ios-pua-arguments.json pua_setup
```

先把实际参数写入 `/tmp/ios-pua-arguments.json`，例如 status 请求。每次仅执行一个命名工具；不要重写 HTTP 客户端或另开裸 WDA 会话控制同一手机。CLI 返回的图片在 JSON 的 image.path 中，必须用图片工具真正查看；base64、路径或预览标题不等于模型看过图。

长输入的 continue_token 只在当前 Runtime 内存中有效，不能复制到下次 CLI 调用。文件入口会在同一 Runtime 中只带 token 续传，直到完成或明确错误；最多续传 64 次，10 分钟后不再发起下一次续传，当前已发出的调用仍等其有界结果。通过可轮询的后台执行跟踪长调用，每次等待不超过 60 秒，不为查看进度中断进程。达到边界或失败时保留输入进度，读取实际字段后只补确认缺失部分，不重发原文。

batch 因长输入暂停时，文件入口先在同一 Runtime 完成该输入，再返回更新后的 results/completed_steps。`stop_reason="input_completed"` 表示 stopped_at 的输入已完成，只发送其后的步骤；提交仍需验收时遵循 `submission_requires_verification`。不会重放之前步骤或自动提交额外动作。调用后的本地错误保留 `uncertain=true`；cleanup_error 不否定已返回的动作证据，不能据此重放。

`local.pid.0`、前台不可用或 XCTest Code 41 按官方 READY 恢复流程排查。恢复允许范围还受本任务归属约束：以前聊天启动的 owned job 或外部服务不能因为插件能停止它就自动停止。归属不明时先诊断并请求协调，不按端口杀进程。
