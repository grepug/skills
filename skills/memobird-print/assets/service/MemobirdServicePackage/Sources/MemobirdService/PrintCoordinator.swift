import CoreText
import Foundation
import MemobirdCore
import MemobirdTransport

struct PrinterStatus: Codable, Sendable {
    var id: String?
    var ready: Bool
    var sending: Bool
    var scanning: Bool
    var message: String
    var autoOffMinutes: Int?
    var desiredAutoOffMinutes: Int?
}
struct PrinterDevice: Codable, Sendable {
    var id: String
    var name: String
    var signal: Int
}
struct ServiceStatus: Codable, Sendable {
    var status: String
    var version: String
    var printer: PrinterStatus
    var activeJobId: String?
    var queuePaused: Bool
    var rendererPid: Int32?
}
struct FontEntry: Codable, Sendable {
    var id: String
    var families: [String]
}
struct FontCatalog: Codable, Sendable {
    var system: [String]
    var imported: [FontEntry]
}

/// The actor serializes hardware ownership, while SQLite keeps recoverable state.
@MainActor
final class PrintCoordinator {
    let store: JobStore
    let log: EventLog
    let printer = BluetoothPrinter()
    let renderer: RendererProcess
    let root: URL
    private var queueTask: Task<Void, Never>?
    private var activeId: String?
    private var acknowledgementId: String?
    private var maintenance: Task<Void, Never>?
    private var selectedPrinterId: String?
    private var desiredAutoOffMinutes: Int?
    private var configuringPrinter = false
    private var shutdownRequested = false

    init(root: URL, rendererURL: URL) throws {
        self.root = root
        store = try JobStore(root: root)
        log = try EventLog(root: root.appendingPathComponent("logs"))
        renderer = RendererProcess(executable: rendererURL)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("fonts"), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: root.appendingPathComponent("printer.json")),
            let saved = try? JSON.decode([String: String].self, from: data)
        {
            selectedPrinterId = saved["id"]
            if let value = saved["autoOffMinutes"].flatMap(Int.init), (0...255).contains(value) {
                desiredAutoOffMinutes = value
            }
        }
        try store.recover()
        try prune()
        printer.onLog = { [weak self] message in
            guard let self else { return }
            event("info", "bluetooth", id: activeId, message: message)
        }
        printer.onAcknowledgement = { [weak self] response in
            guard let self, let id = acknowledgementId else { return }
            try? store.update(id, acknowledgement: response)
        }
        event("info", "service_started", message: "服务启动，渲染器按需运行")
        schedule()
        maintenance = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                guard !Task.isCancelled else { return }
                try? self?.prune()
            }
        }
    }
    func status() throws -> ServiceStatus {
        ServiceStatus(
            status: "running", version: "1.0.0", printer: printerStatus(), activeJobId: activeId,
            queuePaused: try store.hasUncertain(), rendererPid: renderer.processId)
    }
    func printerStatus() -> PrinterStatus {
        PrinterStatus(
            id: printer.connectedId ?? selectedPrinterId, ready: printer.isReady, sending: printer.isSending,
            scanning: printer.isScanning, message: printer.status, autoOffMinutes: printer.autoOffMinutes,
            desiredAutoOffMinutes: desiredAutoOffMinutes)
    }
    func scan() async throws -> [PrinterDevice] {
        guard activeId == nil, !configuringPrinter, !printer.hasConnection else {
            throw ServiceError("printer_busy", "请在没有活动任务且打印机断开时扫描", status: 409)
        }
        printer.scan()
        try await Task.sleep(for: .seconds(13))
        return printer.devices.map {
            PrinterDevice(id: $0.peripheral.identifier.uuidString, name: $0.name, signal: $0.signal)
        }
    }
    func connect(_ id: String?) async throws -> PrinterStatus {
        try beginPrinterConfiguration()
        defer { endPrinterConfiguration() }
        try await printer.connect(id: id ?? selectedPrinterId)
        try await applyPowerPreference()
        try rememberPrinter()
        return printerStatus()
    }
    func power() async throws -> PrinterStatus {
        try beginPrinterConfiguration()
        defer { endPrinterConfiguration() }
        try await printer.connect(id: selectedPrinterId)
        _ = try await printer.readAutoOffMinutes()
        try rememberPrinter()
        return printerStatus()
    }
    func autoOff(minutes: Int) async throws -> PrinterStatus {
        _ = try PrinterPowerProtocol.setAutoOff(minutes: minutes)
        try beginPrinterConfiguration()
        defer { endPrinterConfiguration() }
        try await printer.connect(id: selectedPrinterId)
        try await printer.setAutoOffMinutes(minutes)
        desiredAutoOffMinutes = minutes
        try rememberPrinter()
        event("info", "auto_off_verified", message: "自动关机回读 \(minutes) 分钟；已保存重连偏好")
        return printerStatus()
    }
    private func beginPrinterConfiguration() throws {
        guard activeId == nil, !configuringPrinter else {
            throw ServiceError("printer_busy", "打印机正在处理任务或设置，请稍后重试", status: 409, retryable: true)
        }
        configuringPrinter = true
    }
    private func endPrinterConfiguration() {
        configuringPrinter = false
        scheduleIfNeeded()
    }
    private func applyPowerPreference() async throws {
        guard let desiredAutoOffMinutes, printer.autoOffMinutes != desiredAutoOffMinutes else { return }
        try await printer.setAutoOffMinutes(desiredAutoOffMinutes)
    }
    func disconnect() throws -> PrinterStatus {
        guard !configuringPrinter else { throw ServiceError("printer_busy", "设备设置或回读正在进行", status: 409) }
        if let id = activeId, (try store.get(id)).state == .sending {
            _ = try store.cancel(id)
            queueTask?.cancel()
        }
        printer.disconnect()
        return printerStatus()
    }
    func submit(_ input: PrintRequest, key: String?, mode: String) throws -> Job {
        guard !shutdownRequested else { throw ServiceError("shutting_down", "服务正在退出", status: 503, retryable: true) }
        let job = try store.submit(input, key: key, mode: mode)
        event("info", "job_submitted", id: job.id, message: "任务已接收")
        schedule()
        return job
    }
    func cancel(_ id: String) async throws -> Job {
        let result = try store.cancel(id)
        if activeId == id {
            queueTask?.cancel()
            await renderer.stop()
            if printer.isSending { printer.disconnect() }
        }
        event("info", "job_cancelled", id: id, message: result.state.rawValue)
        schedule()
        return result
    }
    func prune() throws {
        try store.prune()
        try log.prune(before: Date().addingTimeInterval(-30 * 86400))
    }
    func shutdown() async {
        shutdownRequested = true
        maintenance?.cancel()
        queueTask?.cancel()
        if let id = activeId, (try? store.get(id).state) == .sending { try? store.update(id, state: .uncertain) }
        await renderer.stop()
        printer.disconnect()
        await queueTask?.value
        event("info", "service_stopped", message: "服务停止")
    }
    private func schedule() {
        guard queueTask == nil, !shutdownRequested, !configuringPrinter else { return }
        queueTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                activeId = nil
                queueTask = nil
                if !shutdownRequested { scheduleIfNeeded() }
            }
            while !Task.isCancelled, !shutdownRequested {
                do {
                    guard !configuringPrinter else { return }
                    let paused = try store.hasUncertain()
                    guard
                        let job = try store.list().first(where: {
                            $0.state == .queued && ($0.mode == "render" || !paused)
                        })
                    else { return }
                    activeId = job.id
                    await process(job)
                    activeId = nil
                } catch {
                    event("error", "queue_failed", message: "队列存储访问失败")
                    return
                }
            }
        }
    }
    private func scheduleIfNeeded() {
        guard let jobs = try? store.list(), let paused = try? store.hasUncertain(),
            jobs.contains(where: { $0.state == .queued && ($0.mode == "render" || !paused) })
        else { return }
        schedule()
    }
    private func process(_ job: Job) async {
        defer { acknowledgementId = nil }
        do {
            var artifacts = job.artifacts
            if artifacts == nil {
                try store.update(job.id, state: .rendering)
                event("info", "render_started", id: job.id, message: "启动渲染进程")
                let request = try store.request(job.id)
                guard let document = request.document else { throw ServiceError("missing_document", "没有文档内容") }
                artifacts = try await renderer.render(
                    WorkerInput(
                        directory: store.directory(job.id).path,
                        fontsDirectory: root.appendingPathComponent("fonts").path, document: document))
                guard try store.diskUsage() < 2_000_000_000 else {
                    throw ServiceError("quota_exceeded", "渲染结果超过存储配额", status: 507)
                }
                try store.update(job.id, artifacts: artifacts)
                event("info", "render_finished", id: job.id, message: "渲染进程已退出")
            }
            try Task.checkCancellation()
            if job.mode == "render" {
                try store.update(job.id, state: .rendered)
                return
            }
            try store.update(job.id, state: .waitingForPrinter)
            let deadline = Date().addingTimeInterval(120)
            while !printer.isReady {
                do {
                    try await printer.connect(id: selectedPrinterId)
                    try rememberPrinter()
                } catch {
                    try Task.checkCancellation()
                    if let failure = error as? ServiceError, !failure.retryable { throw failure }
                    guard Date() < deadline else {
                        throw ServiceError("printer_unavailable", "120 秒内无法连接打印机", status: 503, retryable: true)
                    }
                    try await Task.sleep(for: .seconds(3))
                }
            }
            try await applyPowerPreference()
            try Task.checkCancellation()
            guard let artifacts else { throw ServiceError("missing_render", "没有打印位图", status: 500) }
            // Persist before the first BLE byte; a crash from here onward is ambiguous.
            try store.update(job.id, state: .sending)
            acknowledgementId = job.id
            event("info", "transmission_started", id: job.id, message: "开始蓝牙发送")
            try await printer.printFiles(artifacts.bitmaps.map { store.directory(job.id).appendingPathComponent($0) })
            try store.update(job.id, state: .transmitted)
            event("info", "transmitted", id: job.id, message: "设备已确认接收全部打印数据，纸张结果需人工确认")
        } catch {
            let state = (try? store.get(job.id).state) ?? .failed
            if shutdownRequested, !state.terminal, state != .sending {
                try? store.update(job.id, state: .queued)
                return
            }
            if state == .cancelled || state == .uncertain { return }
            let failure =
                error as? ServiceError
                ?? ServiceError(
                    error is CancellationError ? "cancelled" : "job_failed",
                    error is CancellationError ? "任务取消" : "任务执行失败", status: 422)
            let next: JobState = state == .sending ? .uncertain : (error is CancellationError ? .cancelled : .failed)
            try? store.update(job.id, state: next, error: failure)
            event("error", next.rawValue, id: job.id, message: failure.code)
        }
    }
    private func rememberPrinter() throws {
        guard let id = printer.connectedId else { return }
        selectedPrinterId = id
        var saved = ["id": id]
        if let desiredAutoOffMinutes { saved["autoOffMinutes"] = String(desiredAutoOffMinutes) }
        try JSON.encode(saved).write(to: root.appendingPathComponent("printer.json"), options: .atomic)
    }
    private func event(_ level: String, _ name: String, id: String? = nil, message: String) {
        do { try log.write(level: level, event: name, jobId: id, message: message) } catch { NSLog("Memobird: 日志写入失败") }
    }
    func fonts() -> FontCatalog {
        let system = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent("fonts"), includingPropertiesForKeys: nil)) ?? []
        return FontCatalog(
            system: system.sorted(),
            imported: files.map { file in
                let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor] ?? []
                return FontEntry(
                    id: file.lastPathComponent,
                    families: descriptors.compactMap {
                        CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String
                    })
            })
    }
    func addFont(_ asset: ResourceAsset) throws -> FontEntry {
        try ResourceAsset.validatePath(asset.path)
        let ext = URL(fileURLWithPath: asset.path).pathExtension.lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext), asset.data.count <= 25_000_000 else {
            throw ServiceError("invalid_font", "字体须为 TTF、OTF 或 TTC，最多 25 MB")
        }
        let id = UUID().uuidString.lowercased() + "." + ext
        let file = root.appendingPathComponent("fonts").appendingPathComponent(id)
        try asset.data.write(to: file, options: .atomic)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor],
            !descriptors.isEmpty
        else {
            try? FileManager.default.removeItem(at: file)
            throw ServiceError("invalid_font", "无法读取字体")
        }
        return FontEntry(
            id: id,
            families: descriptors.compactMap {
                CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String
            })
    }
    func removeFont(_ id: String) throws {
        try ResourceAsset.validatePath(id)
        guard !id.contains("/") else { throw ServiceError("invalid_font", "字体 ID 无效") }
        let file = root.appendingPathComponent("fonts").appendingPathComponent(id)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ServiceError("font_not_found", "字体不存在", status: 404)
        }
        try FileManager.default.removeItem(at: file)
    }
}
