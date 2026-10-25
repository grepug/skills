---
name: memobird-layout
description: 为咕咕机制作 576 点宽 Markdown、HTML/CSS 清单和纸条，离线生成 PDF 与打印位图并检查排版，不提交打印任务。
---

# 咕咕机纸条排版

用于窄纸条的字体层级、留白、换行、图像与分片检查。此 skill 从原 `memobird-print` 内的排版规则和配套纸条 CSS 提取，并补充可移植的离线入口；它不是另一个历史安装的 skill。

## 前提与输入

确认当前内容、纸条用途、字体、资源目录和输出目录。模板是可选样式，不把清单层级强加给照片或其他内容。不改变“确认是否可邀请”等原文判断性质。

- Python 3 标准库；实际渲染需要 macOS 14+ 和 `MemobirdRenderer`。
- 渲染器来自已安装服务 App 的 `Contents/MacOS/MemobirdRenderer`，或用 `memobird-print` 内的离线构建入口生成。只有 skill 文件时不能凭空渲染；详见 [references/rendering.md](references/rendering.md)。
- 资源仅使用本地文件和自备授权字体，不依赖在线图片、CSS 或字体。系统字体可用 `PingFang SC`，不随 skill 分发商业字体。

## 排版原则

位图宽 576 点，G4 标称 300 dpi 对应约 48.77 mm 打印区。57 mm 是纸卷外宽；居中预览估算两侧约 4.12 mm 纸边，实际偏移和纸边未实测，不承诺 CSS 无边距。显示器上的毫米受 DPI 和缩放影响。

HTML/body 清零 margin/padding；576 点内部两侧各留 10 点内容 padding。清单中具体任务标题最大且加粗，总标题次要，描述小而可读，任务前空心勾选框。黑白、留白、细分隔线，避免大黑底。可复用 [assets/receipt.css](assets/receipt.css) 和无私人内容的 [assets/checklist.html](assets/checklist.html)。

浏览器预览可用灰底承托 57 mm 白纸、100% 缩放；标尺、说明和背景放在打印内容之外。浏览器预览不能代替实际 PDF/BMP 检查。

## 离线流程

`SKILL_DIR` 是此 skill 的实际安装目录，`RENDERER` 为渲染器可执行文件路径；输出目录必须不存在。

```sh
python3 "$SKILL_DIR/scripts/offline_render.py" \
  --renderer "$RENDERER" --kind html --input "$SKILL_DIR/assets/checklist.html" \
  --css "$SKILL_DIR/assets/receipt.css" --output-dir ./receipt-preview
```

脚本直接调用独立渲染器，不访问服务、不读取令牌、不扫描或连接蓝牙。输出 `document.pdf`、`stripe-*.bmp`、`result.json` 及诊断日志。Markdown 用 `--kind markdown`，图片用 `--kind image`；需要本地图片/字体时显式传 `--assets-dir`，只选择这份文档需要的小目录。脚本不覆盖已有目录。

检查 PDF 的方向、换行、溢出和缺字，核对位图宽度/总高度、分片交界；BMP 是打印机顶行优先格式，通用查看器可能倒置。1600 行的独立图片交界曾出现实物接缝；需要单 BMP 时，使用 `memobird-print` 的合并脚本和专用导入流程，保留 4000 行软件保护上限。不能用单样张验证代替任意长图的硬件验收。

交付预览路径、尺寸、分片数和仍需人工检查的地方。这个流程止于预览；后续打印使用 `memobird-print` 并遵循该份内容的打印授权和幂等记录。
