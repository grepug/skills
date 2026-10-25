# 安装、重建与离线验证

仅安装 skill 不会安装服务。使用仓库默认安装器可安装 `memobird-print`、`memobird-layout`；未合并分支的用法见仓库 README。

## 依赖

运行服务：macOS 14+；重建：完整 Xcode、Swift 6.2+、Python 3、XcodeBuildMCP CLI（`xcodebuildmcp` 在 PATH）。系统框架包括 CoreBluetooth、AppKit、WebKit、ImageIO、CoreText、SQLite。运行时不需要 Xcode 或 AppKey。

服务 SwiftPM 依赖：Hummingbird 2.28.0、ArgumentParser 1.8.2、NIO ≥2.101.0、SwiftLog ≥1.14.0；完整传递版本保留在 `assets/service/MemobirdServicePackage/Package.resolved`。干净机器构建服务需要下载这些依赖。渲染器附带 markdown-it UMD 和对应 MIT 许可证；不分发厂商 SDK、字体或任何预编译 App。

`SKILL_DIR` 均为实际安装的 `memobird-print` 目录。以下工作目录选择可写的全新目录；按所在机器的缓存规范设置 `TMPDIR`，不要更改系统临时目录设置。

## 不安装服务的离线验证

```sh
python3 "$SKILL_DIR/scripts/test_helpers.py"
python3 "$SKILL_DIR/scripts/prepare_offline.py" --work-dir ./memobird-offline
xcodebuildmcp swift-package test --package-path "$PWD/memobird-offline"
xcodebuildmcp swift-package build --package-path "$PWD/memobird-offline" --target-name MemobirdRenderer
```

此包直接复用随附核心、SQLite 封装、渲染器和核心测试源码，无 SwiftPM 网络依赖、HTTP 服务、CLI 安装器或蓝牙 transport。测试只对合成数据验证存储、幂等、协议分包、ACK/补传、自动关机命令编码、专用 BMP 和超时，不连接设备、不发送数据、不设置设备。

渲染器通常位于 `memobird-offline/.build/out/Products/Debug/MemobirdRenderer`；不同 CLI/toolchain 也可能在 `.build/debug/`。使用构建日志中的实际路径。把它作为 `memobird-layout` 离线入口的 `--renderer`，产出预览 PDF/BMP。

## 完整服务构建（不安装）

```sh
python3 "$SKILL_DIR/scripts/build_service.py" --work-dir ./memobird-build
```

它复制源码到新目录，通过 XcodeBuildMCP release 构建并以系统 `codesign` 本地签名，输出 `memobird-build/output/MemobirdService.app` 和 CLI；不运行 `service install/start`，不修改 TCC。可通过 `MEMOBIRD_SIGN_IDENTITY` 选择自己的稳定签名身份，默认 ad-hoc。打包器也支持显式构建产物路径：`scripts/package_service.py --products DIR --output-dir NEW_DIR`。

## 用户要求安装服务时

安装会替换用户目录中的服务 App/CLI、写 LaunchAgent、创建或复用私有令牌，并启动后台服务；第一次蓝牙访问可能由 macOS 请求许可。先说明现有安装是否会被替换，再在安装授权范围内运行：

```sh
./memobird-build/output/memobird service install --bundle ./memobird-build/output/MemobirdService.app
```

安装位置按当前用户 home 推导：`~/Applications/咕咕打印服务.app`、`~/.local/bin/memobird`、`~/Library/LaunchAgents/local.memobird.service.plist`。不写死用户名或原开发机路径。ad-hoc 重建可能需要重新授予蓝牙访问；不要自动修改系统权限。

本机服务默认监听 `0.0.0.0:8765`，CLI 默认连接 `http://127.0.0.1:8765`；所有 `/v1` 接口必须携带 Bearer token。按需由部署者配置 `MEMOBIRD_HOST`/`MEMOBIRD_PORT`，不要意外暴露端口。远程客户端配置 `MEMOBIRD_URL` 和 `MEMOBIRD_TOKEN_FILE`；令牌只放用户私有文件，不输出、不提交仓库。

连接打印机及实际打印是后续独立操作，仍需当前任务授权。安装/离线测试通过不能证明 BLE 兼容、纸边、长图接缝或完整出纸。Intel Mac、macOS 14 和不同固件需分别验收。
