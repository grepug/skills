# 连续纸条的1600行接缝与单BMP导入

## 已知证据与状态

独立 BMP 在 1600 行分片交界曾出现白带/文字错位，即使栅格连续且设备确认接收全部包。合成单张 576×1830 BMP 的一次样张获得完整纸张反馈；这里只保留方法，不附用户内容、任务 ID 或日志。该反馈不能证明任意长图可靠，具体固件机制也未确认。

## 按任务使用

先通过`memobird render image --help`确认支持`--printer-bitmap`。该选项只接受打印机专用BMP：576点宽、未压缩1位、62字节头、正高度但顶行优先、白色索引0/黑色索引1。它不是任意普通BMP导入接口。无该选项的服务会对`print image`重新渲染并切片，不能把上传一张长图等同于发送一个BMP。

只需合并已检查的服务位图时：

```sh
python3 SKILL_DIR/scripts/merge_printer_bmp.py --output document.bmp stripe-0000.bmp stripe-0001.bmp
memobird render image document.bmp --printer-bitmap --idempotency-key "$MEMOBIRD_RENDER_KEY" --wait --json
```

将`SKILL_DIR`替换为本技能的实际目录。合并脚本不打印。它保留原行数据、去掉后续BMP头并修正总高度/长度；不插删行、不缩放或重新抖动。4000行只是与现有编码器一致的保守软件保护上限，可靠硬件高度上限仍待验证；不要解除上限来处理任意长图。

下载新render的位图和PDF，确认恰好一个BMP、尺寸与合并前总高度一致、位图SHA256与合并输入一致、PDF方向正确。确认只是预览时到此停止。用户已明确批准该份试印后，以保存的新打印幂等键提交一次：

```sh
memobird print rendered RENDER_ID --idempotency-key "$MEMOBIRD_REQUEST_KEY" --wait --json
```

只查询原job等待状态，不确定时不自动重印。`transmitted`仅表示设备确认接收。请用户重点检查1600行交界、完整页脚、方向及缺行。实际反馈保存在本任务记录；获用户确认后再更新本节的验证状态。

## 范围

`--printer-bitmap`仅改变该任务的图片导入，普通HTML/Markdown/图片的默认渲染、服务队列与蓝牙流控不变。不得直接改任务数据库/已保存位图、伪造render产物或手工补发BLE字节来绕过正常提交及幂等记录。
