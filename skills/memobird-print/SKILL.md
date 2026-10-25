---
name: memobird-print
description: 通过本机或远程 Memobird 服务排版、预览及打印 Markdown、图片和 HTML/CSS，管理字体、判断打印结果并处理异常，避免重复出纸。用于调用 MEMOBIRD G4HD C 打印机，不用于一般文档导出。
---

# 咕咕机打印

使用 `memobird`（通常安装为 `~/.local/bin/memobird`），不需要 AppKey。默认服务为 `http://127.0.0.1:8765`；远程服务通过 `MEMOBIRD_URL` 和 `MEMOBIRD_TOKEN_FILE` 配置。令牌由 CLI 从文件读取，勿输出到对话、日志或命令参数。

## 前提与安装

需要已配置的本机或远程咕咕打印服务，服务协议与 `--printer-bitmap` 能力须与此 skill 对应。尚未安装时，使用随附源码和 [references/installation.md](references/installation.md)；仅安装 skill 不会安装或启动服务。构建需要 macOS 14+、完整 Xcode/Swift 6.2+、Python 3、XcodeBuildMCP CLI；离线核心测试和渲染器可不下载 SwiftPM 网络依赖。正常服务构建的依赖版本在 `assets/service/MemobirdServicePackage/Package.swift` 和 `Package.resolved` 中。

使用前确定输入文件、资源目录、预览输出目录和份数。只整理或预览不授权蓝牙连接、设置变更或出纸；安装/升级服务会写入 App、CLI、LaunchAgent 和令牌配置，须在用户请求安装时执行。后文打印示例仅用于已有打印授权的任务。

离线验证入口：`scripts/prepare_offline.py` 复制核心/渲染器和测试到显式工作目录，不加载 CoreBluetooth、不启动 HTTP 服务。`scripts/test_helpers.py` 验证 BMP 合并与拒绝无效输入；细节见安装说明。

## 调用

先用 `memobird service status --json` 检查服务。未启动时可在用户请求打印的现有授权范围内执行 `memobird service start`。打印机离线时检查 `printer status`，需要时 `printers scan` 后 `printer connect --id UUID`。

`memobird printer power --json` 实际查询自动关机时间；`autoOffMinutes` 是设备回读值，`desiredAutoOffMinutes` 只是保存的偏好，不能混为一谈。用户要求保持开机时，可用 `printer auto-off --minutes 0 --json` 关闭定时关机并回读确认，服务重连时恢复该偏好；1–255 是分钟数。设置忙时先等待原任务，不能断连或取消打印来抢占设置。查询/设置不会出纸；超时或回读不一致不算设置成功，电池耗尽、断电和手动关机不受该设置控制。

- Markdown：`memobird print markdown note.md --idempotency-key "$MEMOBIRD_REQUEST_KEY" --wait --json`
- 图片：`memobird print image photo.png --idempotency-key "$MEMOBIRD_REQUEST_KEY" --wait --json`
- HTML/CSS：`memobird print html page.html --css print.css --assets-dir ./assets --font 'PingFang SC' --font-size 26 --idempotency-key "$MEMOBIRD_REQUEST_KEY" --wait --json`
- stdin：将内容传给 `memobird print markdown - --idempotency-key "$MEMOBIRD_REQUEST_KEY" --wait --json`；保留输入供同内容重试。
- 只排版：将 `print` 换成 `render`；用 `jobs artifact ID document.pdf --output ./preview.pdf` 下载预览。确认可打印后可用 `print rendered ID --wait --json`，避免再次渲染。

文件中的图片、CSS、字体引用使用相对于资源目录的路径。未指定 `--assets-dir` 时打包输入文件目录内支持的资源；大目录应显式选择较小目录。HTML 页面脚本禁用，支持 CSS、打印媒体样式和字体。字体用 `fonts list/add/remove` 管理；`fonts add` 返回字体家族名，再通过 `--font` 使用。网页字体可作为资源配合 `@font-face`。

## 排版与预览

576 点宽的 HTML/CSS、纸卷尺寸估算和可复用清单模板见配套 `memobird-layout` skill。它从原打印 skill 的排版规则和实际 CSS 提取；不是另一个历史安装的 skill。默认以用户当前的内容和样式要求为准。

先检查实际渲染 PDF 和打印位图的方向、换行、溢出、缺字与分片交界。曾观察到独立 BMP 在 1600 行分片交界出现实体白带；单 BMP 合并和按任务导入见 [references/single-bitmap.md](references/single-bitmap.md)。单样张反馈不能证明任意长度均可靠。

## 授权与请求记录

只在用户要求实际打印时提交 `print`；排版、查看预览使用 `render`。普通打印请求已构成授权；用户要求“先预览、同意后打印”时，先展示实际预览并等明确同意，再打印该 `renderId`。一次打印授权不等于部分出纸后自动重印的授权。

首次提交前，为本次打印生成一个 UUID 幂等键并保存；示例中的 `MEMOBIRD_REQUEST_KEY` 必须从该记录加载。CLI 不指定键时会每次生成新键，不能依赖它来防止重试重复打印。

在当前任务的工作目录保存服务 URL、幂等键、输入或 `renderId`、返回的打印 `jobId`、用户批准的内容/份数及纸张反馈；不保存令牌。交接给其他 agent 或恢复会话时，先读记录并查询原任务。预览 ID 和实际打印 ID 是两个任务，不要混用；同一次请求的恢复复用原键。

## 判断结果

以 `jobs get ID --json` 的 `state` 和 `error` 为准。`--wait` 返回、CLI 退出码 0、HTTP 202、蓝牙保持连接或任意一条设备回包，都不能单独证明完整出纸；特别是 `print rendered --wait` 可能正常退出但返回失败状态。

| 状态 | 含义与下一步 |
|---|---|
| `queued` / `rendering` / `waiting_for_printer` | 任务仍在处理。查询原 ID，检查 `service status --json` 的 `queuePaused`；不要再提交一份。 |
| `rendered` | 只生成预览，没有出纸。需要实际打印授权后才提交 `print rendered`。 |
| `sending` | 包括发送、设备要求的补传及等待最终确认。等待原任务；不要并行提交、断连或重启来“重试”。 |
| `transmitted` | 当前修复版已收到设备对全部包的最终接收确认，仍不证明纸张完整。报告“设备已确认接收，纸张待确认”；需要确认实际结果时，请用户检查末尾内容、裁切/方向及缺行。 |
| `failed` | 查看 `error` 和任务日志。确认从未开始蓝牙发送后，修复输入/连接原因，才可在原授权范围内以新键创建替代任务。旧键仍会返回原失败任务。 |
| `uncertain` | 可能已经部分出纸；服务暂停后续打印。停止自动提交，先请用户检查纸张，再按下节处理。 |
| `cancelled` | 不能据此判断未出纸；可能是用户确认了一次不确定任务。查看错误、发送日志及纸张反馈。 |

用户确认完整出纸后，才报告“完整打印”。历史任务或版本未知的远程服务可能只检查蓝牙提交；没有最终确认的证据时，不声称“设备已确认接收”。若用户报告半张纸或缺行，即使状态为 `transmitted`，也按部分出纸处理，暂停 agent 的后续提交并排查，不能用该状态否定用户反馈。

## 异常与防重复打印

- **等待或网络超时，已有 ID**：`memobird jobs get ID --wait --json` 查询同一任务；不再执行 `print`。`wait_timeout` 不表示服务取消了任务。
- **响应丢失，没有 ID**：恢复同一服务连接后，用相同请求和保存的同一幂等键重新提交，取回原任务。输入、附件或服务 URL 不能悄悄改变；`idempotency_conflict` 时核对原记录，不能换新键绕过冲突。`error.retryable=true` 也不允许自动换键。
- **设备要求补传**：服务在原任务内等待 1.5 秒后，从已确认位置之后继续，最多恢复 3 次。agent 不手工发送 BLE 数据、不新建补传任务；恢复耗尽、设备状态异常或最终确认超时会转为 `uncertain`。
- **半张纸、`uncertain` 或发送中断**：查看原任务与日志，询问最后打印内容、缺纸/指示灯及供电情况。先完成可在不出纸情况下进行的诊断与修复；重印前说明会再次输出已打印部分，取得用户明确重印指令。不要按估计位置跨任务续打剩余字节，也不要主动清除不确定状态、改数据库或删除记录来解除暂停。
- **用户确认不重印**：对 `uncertain` 执行 `memobird jobs cancel ID --json`，确认该任务并解除其暂停；告知解除后其他排队打印可能继续。该操作不证明此前没有出纸。
- **用户明确要求重印**：先确认原任务已终止；若为 `uncertain`，用 `jobs cancel ID` 确认原任务。再为用户批准的新一份生成并保存新键，优先 `memobird print rendered RENDER_ID --idempotency-key "$MEMOBIRD_REQUEST_KEY" --wait --json`，保存新的打印 ID。原幂等键不会触发重印。若仍有其他不确定任务，不得为赶进度批量确认它们。

取消正在发送的任务可能留下半张纸。对 `transmitted` 调用 `jobs cancel` 不会撤回纸张，也不能修复部分出纸；不把取消当作通用重试步骤。

## 日志与保留

`memobird logs export --job ID --json` 查看原任务的发送、补传、最终确认和错误；`logs tail --follow` 跟随日志。单条 `RX FF01` 或 FF03 信用额度不是成功证据，应结合任务最终状态及纸张反馈。对外报告附上任务 ID、状态、错误码和已确认的纸张结果，避免只说“成功”或“失败”。

内容及预览保留 7 天，任务和日志保留 30 天。`logs prune` 按保留策略清理。存储配额不足时可用 `jobs purge ID` 提前删除终态任务文件，保留历史和幂等记录；活动任务不能清理。尚在排查或可能重印的预览不要提前清理；预览过期则重新渲染，内容或排版变化时重新遵守用户的预览确认要求。

HTTP 调用及资源格式参阅 [references/http.md](references/http.md)。详细命令以 `memobird COMMAND --help` 为准。
