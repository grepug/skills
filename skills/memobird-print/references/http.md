# HTTP 调用

所有 `/v1` 接口需要 `Authorization: Bearer TOKEN`；不支持浏览器跨域。优先使用 CLI，它会读取令牌并将本地资源打包。HTTP 返回错误为 `{"error":{"code":"...","message":"...","retryable":false,"status":400}}`。

提交 `POST /v1/jobs`（实际打印）或 `POST /v1/renders`（只渲染），设置 `Idempotency-Key`：

```json
{"document":{"kind":"markdown","content":"# 你好\n\n![图片](images/a.png)","css":"h1 { font-size: 38px; }","font":"PingFang SC","fontSize":26,"assets":[{"path":"images/a.png","data":"BASE64","mimeType":"image/png"}]}}
```

`kind` 为 `markdown`、`html` 或 `image`。图片任务提供一个图片 asset，或在 content 中提供图片 data URL。资源路径必须是相对路径，不能穿越目录；data 为 base64。HTML 支持完整文档和片段，资源中的 CSS 可使用相对图片/字体路径以及远程 HTTP(S) URL。

打印已有渲染结果：`POST /v1/jobs`，body 为 `{"renderId":"UUID"}`。两种输入互斥。返回 HTTP 202 和任务对象；202 只表示请求已接收，保存返回的打印 ID（不同于 renderId），再查询 `GET /v1/jobs/ID`。取消用 `POST /v1/jobs/ID/cancel`，清理终态任务文件用 `POST /v1/jobs/ID/purge`（保留历史和幂等记录）；下载 `GET /v1/jobs/ID/artifacts/document.pdf` 或 artifacts.bitmaps 中的文件名。

状态：queued → rendering → rendered（预览）或 waiting_for_printer → sending → transmitted；失败为 failed，取消为 cancelled，发送结果无法判断为 uncertain。`sending` 包括设备请求的补传与等待最终确认；当前修复版 `transmitted` 要求设备确认接收全部包，纸张完整性仍需用户确认。不确定任务暂停打印队列，查看纸张后按 [SKILL.md 的异常处理规则](../SKILL.md#异常与防重复打印)处理，不自动重印。

有打印 ID 时优先 GET 查询，不再 POST。POST 响应丢失且没有 ID 时，对同一服务复用完全相同的 body 与 `Idempotency-Key`，取回原任务；不能因超时、`retryable=true` 或 409 冲突自动换键。服务内部的包恢复不创建新任务；用户明确授权的新一份重印才使用新键。确认不确定任务会解除其队列暂停，可能使其他排队任务继续，不能以取消掩盖未解决的部分出纸。

其他接口：`GET /v1/status`、`GET /v1/paths`、`GET /v1/printers`、`POST /v1/printers/scan`、`POST /v1/printer/connect`（body 可为 `{}` 或 `{"id":"设备 UUID"}`）、`POST /v1/printer/disconnect`、`GET /v1/fonts`、`POST /v1/fonts`（单个 ResourceAsset）、`DELETE /v1/fonts/ID`、`GET /v1/logs?job=ID&level=info&since=ISO8601`、`POST /v1/maintenance/prune`。

电源设置：`GET /v1/printer/power` 实际回读设备信息；`POST /v1/printer/auto-off`，body 为 `{"minutes":0}` 关闭定时自动关机，或 1–255 分钟。POST 仅在回读与请求一致后返回 200，并保存重连偏好。结果中的 `autoOffMinutes` 为本次连接中读取的设备值，`desiredAutoOffMinutes` 为保存的期望；断连时省略前者。忙时返回 409，回读失败或超时不能算设置成功；不会打印纸张。

单次 HTTP body 最大 64 MB；文档和额外 CSS 合计 2 MB，单个资源 25 MB，资源总计 45 MB/256 项，打印高度 30,000 像素。服务数据配额 2 GB。

跨网络访问时配置 `MEMOBIRD_URL=https://你的域名`，并提供具有访问权限的令牌文件。Cloudflare Tunnel 的源服务为 `http://127.0.0.1:8765`；保留服务 Bearer 鉴权，不将令牌放入 URL。
