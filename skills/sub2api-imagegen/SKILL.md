---
name: sub2api-imagegen
description: 使用用户自备的 Sub2API base URL 和 API key 生成本地图片。适用于没有内置生图工具的 agent 调用 gpt-image-2 文生图，或上传用户指定的本地参考图进行生图；不支持蒙版局部编辑。
---

# Sub2API 生图与参考图

运行随附的 `scripts/sub2api-imagegen.mjs`，无需内置生图工具、npm 包、Tell 或其他服务。需要 Node.js 20.3+、macOS/Linux 和可用的 Sub2API 图片接口。

以下命令从本 skill 目录执行；安装在别处时使用脚本绝对路径。遵守所在宿主的文件、凭据和网络权限规则。用户要求生图可授权该次收费请求；只要求安装/初始化时不要顺便生图。

## 首次配置

```bash
node scripts/sub2api-imagegen.mjs init
```

在 `~/.sub2api-imagegen/.env` 创建空白配置并通过系统编辑器打开（macOS TextEdit；Linux 默认编辑器）。请用户自己在文件内填写 `SUB2API_BASE_URL` 和 `SUB2API_API_KEY`，保存后告知完成；等待用户填好再继续。不要让用户把密钥贴进聊天，不要读取、回显或提交真实配置，也不要把密钥传进命令参数。`.env` 是本机明文配置，请用户妥善保管；新目录权限为 700，文件为 600。重复初始化不会覆盖已有内容。

无桌面时可用 `init --no-open` 创建同一模板，再让用户用本机编辑器打开该路径。编辑器启动失败仍保留模板。配置支持逐行 `KEY=value`、注释和同一行配对引号，值按字面读取，不执行 shell、不展开变量。base URL 可带或不带 `/v1`，可带路由前缀；使用 HTTPS，本机 loopback 服务可用 HTTP。拒绝 URL 内的账号密码、query、fragment 和所有重定向。

用户填写完成后，仅运行：

```bash
node scripts/sub2api-imagegen.mjs status
```

`ready: true` 只证明两项已填且 URL 格式可用，不验证密钥或余额。未齐全时退出码为 1；让用户在本地补全，不读回文件。仅生图工具进程会读取配置用于请求。

## 生成与交付

根据用户意图确定提示词、尺寸和输出目录；已有信息足够时直接执行。每次调用只提交一张：

```bash
node scripts/sub2api-imagegen.mjs generate --prompt '雨后的安静庭院，柔和晨光' --aspect-ratio 9:16 --output-dir ./images
# 较长提示词可存为 UTF-8 文件：
node scripts/sub2api-imagegen.mjs generate --prompt-file ./prompt.txt --output-dir ./images
# 已获用户授权上传的本地参考图；每张重复一次 --image，顺序与提示词中的编号对应：
node scripts/sub2api-imagegen.mjs generate --prompt '保留图1的主体，采用图2的配色' --image /absolute/subject.png --image /absolute/palette.jpg --output-dir ./images
```

无参考图时仍使用同步 `POST /v1/images/generations` JSON；有 `--image` 时使用 `POST /v1/images/edits`，通过 multipart 重复 `image[]` 按输入顺序上传，文件名使用通用名称而非本机路径。两种模式均为 `gpt-image-2`、`quality: low`、`n: 1`、base64 返回。`--aspect-ratio` 为 `auto`（默认）、`1:1`（1024×1024）或 `9:16`（864×1536）；`--background` 为 `auto`（默认）或 `opaque`。这些是请求尺寸，交付时以返回的实际宽高为准。没有蒙版局部编辑、远程图片 URL、透明背景、高分辨率、其他模型或服务 fallback。

只上传用户明确指定并授权发送到其配置服务的图片；生图请求本身不授权读取或上传其他文件。已有授权足够时无需重复询问。`--image` 只接受绝对路径的普通本地 PNG/JPEG/WebP 文件，按实际容器识别格式；拒绝最终文件符号链接，解析父目录后以不跟随符号链接的方式打开并检查文件身份及读前/读后变化。文件在读后到提交间的再次修改不会改变已读取的上传快照。不要扫描目录挑图或把私有路径、图片字节/base64 写进日志。客户端限制为最多 5 张、每张不超过 20 MiB、合计不超过 50 MiB，并非所有上游部署的统一上限；代理可能有更低限制。

multipart 接口依据 [Sub2API 固定版本实现](https://github.com/Wei-Shaw/sub2api/blob/ba81c7fd758e425d67f856d601147ef0c5263d3f/backend/internal/service/openai_images.go)；实际部署版本、账号通道和代理兼容性仍需用户配置后验证。接口不兼容或失败时，不能自动切换 JSON、移除参考图或改用其他接口重发。

默认输出目录为当前目录的 `generated-images`。成功返回 JSON，包含绝对 `path`、实际格式/宽高、字节数、模型和请求质量。输出按实际 PNG/JPEG/WebP 格式命名，使用随机新文件名、独占创建，避免覆盖；单张最多 50 MiB。检查图片后，使用宿主支持的文件链接、附件或本地路径交付；不能假定每个宿主都能发送附件。图片检查验证容器结构和尺寸，不保证像素流可解码或内容符合提示词。

默认 120 秒请求总超时包含上传、响应头和响应体，可用 `--timeout-seconds` 缩短；SIGINT/SIGTERM 取消本地等待及上传，不能保证服务端工作撤销。错误只输出非敏感类别，不展示上游正文。不要启用原始 HTTP 日志或输出错误栈。超时、取消、连接中断或响应/保存异常都可能已经收费，CLI 不重试；告知用户结果及可能收费的边界，再根据其指示处理，不能自动再发一笔请求。

## 离线验证

`node --test scripts/sub2api-imagegen.test.mjs` 使用临时 HOME、`scripts/fixtures.json` 和本地 mock HTTP，验证初始化、独立复制、参考图 multipart 字节/顺序、上传前文件预检、错误、上传超时/取消及真实格式保存。`scripts/image.mjs` 仅检查图片容器。测试不读取真实配置、不打开真实编辑器、不调用付费接口。
