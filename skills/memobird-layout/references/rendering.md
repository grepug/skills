# 离线渲染器

本 skill 不内置二进制。已有服务时，显式选择该 App 的 `Contents/MacOS/MemobirdRenderer`；只运行这个短生命周期助手，不运行服务入口。它链接 AppKit/WebKit/ImageIO，不链接 CoreBluetooth，不需要打印令牌。页面脚本禁用，但图片、CSS 和字体由渲染器处理。只使用可信的本地资源；脚本拒绝明文网络 URL，不替代操作系统网络隔离。

没有服务时，用配套 `memobird-print` skill 的 `scripts/prepare_offline.py` 准备不含网络依赖的 Swift 包，再通过 XcodeBuildMCP 构建；参阅该 skill 的安装说明。两个 skill 可分别安装；`memobird-layout` 需要显式提供已经存在的渲染器。

离线入口支持 HTML、Markdown 和图片，`--css` 附加样式，`--assets-dir` 显式打包小资源目录。字体文件随资源提交并仅在进程内注册。无 `--assets-dir` 时不自动打包整个输入目录。资源目录内禁止符号链接，不包含隐藏文件。`--printer-bitmap` 只用于已经检查的专用 BMP，限制同打印 skill。

输出目录必须不存在。`result.json` 内的 `artifacts` 列出 PDF、位图和总高度；失败时查看 `error` 与 `renderer.log`，不能把生成文件等同于打印成功。每条 BMP 宽 576、行步长 72 字节、白 0 黑 1、正高度但顶行优先。方向判断以 PDF 和行数据为准。

这些 PDF 的坐标以渲染点为单位，不能直接把 PDF 页面的 576 pt 当成实际纸宽。打印机发送位图使用 576 点宽；屏幕或桌面打印 PDF 的尺寸不代表热敏机实体尺寸。
