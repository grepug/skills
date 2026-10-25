import CoreBluetooth
import Foundation
import MemobirdCore

/// Owns the local BLE connection and serializes SDK-derived printing and device settings.
@MainActor
public final class BluetoothPrinter: NSObject {
    public struct Device {
        public let peripheral: CBPeripheral
        public let name: String
        public let signal: Int
    }

    public private(set) var devices: [Device] = []
    public private(set) var status = "请开机，然后扫描附近的打印机"
    public private(set) var logs: [String] = []
    public private(set) var isScanning = false
    public private(set) var isReady = false
    public private(set) var isSending = false
    public private(set) var isConfiguring = false
    public private(set) var autoOffMinutes: Int?
    public var onChange: (() -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var subscribed: Set<String> = []
    private var flow = PrinterFlowControl()
    private var pending = Data()
    private var totalBytes = 0
    private var scanRequested = false
    private var deadline: Task<Void, Never>?
    private var scanDeadline: Task<Void, Never>?
    private var controlPending = Data()
    private var controlCommand: UInt8?
    private var controlReply: PrinterReply?
    private var controlDecoder = PrinterReplyDecoder()
    private var controlError: ServiceError?

    public var hasConnection: Bool { peripheral != nil }

    public func scan() {
        guard peripheral == nil else { return }
        scanRequested = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        } else {
            setStatus("请开启 Mac 蓝牙，并允许咕咕打印服务使用蓝牙")
        }
    }

    public func connect(at index: Int) {
        guard devices.indices.contains(index), peripheral == nil else { return }
        stopScan()
        let selected = devices[index]
        peripheral = selected.peripheral
        selected.peripheral.delegate = self
        central?.connect(selected.peripheral)
        setStatus("正在连接 \(selected.name)…")
        armDeadline(seconds: 15, message: "连接或服务发现超时，请断开后重试")
    }

    public func disconnect() {
        stopScan()
        deadline?.cancel()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        resetConnection()
        setStatus("已断开；如刚才发送过内容，请检查纸张后再重试")
    }

    public var onLog: ((String) -> Void)?
    public var onAcknowledgement: ((String) -> Void)?
    private var transmission: PrintTransmission?
    private var recovery: Task<Void, Never>?
    private var waitingForAcknowledgement = false
    private var sendError: ServiceError?
    public override init() { super.init() }
    public var connectedId: String? { peripheral?.identifier.uuidString }

    public func connect(id: String?) async throws {
        if isReady, id == nil || connectedId?.lowercased() == id?.lowercased() { return }
        if hasConnection { disconnect() }
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        for _ in 0..<50 {
            if central?.state == .poweredOn { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if central?.state == .unauthorized {
            throw ServiceError("bluetooth_permission", "请在系统设置 → 隐私与安全性 → 蓝牙允许咕咕打印服务", status: 403)
        }
        guard central?.state == .poweredOn else {
            throw ServiceError("bluetooth_unavailable", status, status: 503, retryable: true)
        }
        if let id, let uuid = UUID(uuidString: id),
            let selected = central?.retrievePeripherals(withIdentifiers: [uuid]).first
        {
            stopScan()
            peripheral = selected
            selected.delegate = self
            central?.connect(selected)
            armDeadline(seconds: 15, message: "连接超时")
        } else {
            scan()
            for _ in 0..<120 {
                if let index = devices.firstIndex(where: {
                    id == nil || $0.peripheral.identifier.uuidString.lowercased() == id?.lowercased()
                }) {
                    connect(at: index)
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        for _ in 0..<160 {
            if isReady { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        disconnect()
        throw ServiceError("connection_failed", status, status: 503, retryable: true)
    }

    public func printFiles(_ files: [URL]) async throws {
        guard isReady, !isSending, !isConfiguring else {
            throw ServiceError("printer_not_ready", status, status: 409, retryable: true)
        }
        transmission = try PrintTransmission(files: files)
        totalBytes = transmission?.byteCount ?? 0
        pending = Data()
        waitingForAcknowledgement = false
        sendError = nil
        isSending = true
        setStatus("开始发送 \(transmission?.packetCount ?? 0) 个打印数据包")
        armDeadline(seconds: max(90, min(900, totalBytes / 3000 + 30)), message: "发送超时，结果不确定")
        drain()
        do {
            while isSending { try await Task.sleep(for: .milliseconds(50)) }
            if let sendError { throw sendError }
        } catch {
            if isSending { disconnect() }
            throw error
        }
    }

    public func readAutoOffMinutes() async throws -> Int {
        try beginConfiguration()
        defer { isConfiguring = false }
        return try await queryAutoOff()
    }

    /// A successful write is insufficient: read parameter 19 back before confirming.
    public func setAutoOffMinutes(_ minutes: Int) async throws {
        let packet = try PrinterPowerProtocol.setAutoOff(minutes: minutes)
        try beginConfiguration()
        defer { isConfiguring = false }
        if try await queryAutoOff() != minutes {
            autoOffMinutes = nil
            _ = try await exchange(packet, command: 3)
            guard try await queryAutoOff() == minutes else {
                throw ServiceError("setting_not_applied", "设备回读值与请求不一致，不能确认关闭自动关机", status: 502)
            }
        }
        setStatus(minutes == 0 ? "已回读确认：自动关机已关闭" : "已回读确认：\(minutes) 分钟后自动关机")
    }

    private func beginConfiguration() throws {
        guard isReady, !isSending, !isConfiguring else {
            throw ServiceError("printer_busy", "请在打印机连接且空闲时设置自动关机", status: 409)
        }
        isConfiguring = true
    }

    private func queryAutoOff() async throws -> Int {
        let reply = try await exchange(PrinterPowerProtocol.query, command: 2)
        let minutes = try PrinterPowerProtocol.autoOffMinutes(in: reply)
        autoOffMinutes = minutes
        return minutes
    }

    private func exchange(_ packet: Data, command: UInt8) async throws -> PrinterReply {
        controlDecoder = PrinterReplyDecoder()
        controlReply = nil
        controlError = nil
        controlCommand = command
        controlPending = packet
        defer {
            controlCommand = nil
            controlPending.removeAll()
        }
        log("发送设备命令 \(command)")
        drain()
        let limit = Date().addingTimeInterval(10)
        while Date() < limit {
            try Task.checkCancellation()
            if let controlError { throw controlError }
            if let controlReply { return controlReply }
            guard isReady else { throw ServiceError("device_disconnected", "设置期间设备断开，未确认设置", status: 503) }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ServiceError("device_command_timeout", "设备设置或回读超时，不能确认自动关机状态", status: 504, retryable: true)
    }

    func copyLogs() -> String { logs.joined(separator: "\n") }

    private func beginScan() {
        guard let central, peripheral == nil else { return }
        devices.removeAll()
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        setStatus("正在扫描 MEMOBIRD G4HD…")
        scanDeadline?.cancel()
        scanDeadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self else { return }
            stopScan()
            setStatus(devices.isEmpty ? "未找到打印机：请确认开机，并断开手机 App 的连接" : "扫描完成，请选择打印机并连接")
        }
    }

    private func stopScan() {
        central?.stopScan()
        scanDeadline?.cancel()
        scanRequested = false
        isScanning = false
    }

    private func resetConnection() {
        peripheral?.delegate = nil
        peripheral = nil
        writeCharacteristic = nil
        subscribed.removeAll()
        flow = PrinterFlowControl()
        controlError = ServiceError("device_disconnected", "设备连接已断开，设置未确认", status: 503)
        controlCommand = nil
        controlReply = nil
        controlPending.removeAll()
        autoOffMinutes = nil
        isConfiguring = false
        if isSending { sendError = ServiceError("transmission_interrupted", "发送中断，可能已经部分打印", status: 409) }
        recovery?.cancel()
        recovery = nil
        transmission = nil
        waitingForAcknowledgement = false
        pending.removeAll()
        isSending = false
        isReady = false
    }

    private func setStatus(_ message: String) {
        status = message
        log(message)
    }

    private func log(_ message: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard))  \(message)"
        logs.append(line)
        if logs.count > 400 { logs.removeFirst(logs.count - 400) }
        onLog?(message)
        onChange?()
    }

    private func armDeadline(seconds: Int, message: String) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            let wasSending = isSending
            disconnect()
            if wasSending { sendError = ServiceError("transmission_timeout", message, status: 409) }
            setStatus(message)
        }
    }

    private func checkReady() {
        guard writeCharacteristic != nil, subscribed.isSuperset(of: ["FF01", "FF03"]) else { return }
        guard !isReady else { return }
        deadline?.cancel()
        isReady = true
        setStatus("已连接 \(peripheral?.name ?? "MEMOBIRD")，可以试打")
    }

    private func drain() {
        guard let peripheral, let writeCharacteristic else { return }
        if controlCommand != nil {
            while peripheral.canSendWriteWithoutResponse, !controlPending.isEmpty {
                guard
                    let chunk = flow.nextChunk(
                        from: controlPending, maximumLength: peripheral.maximumWriteValueLength(for: .withoutResponse))
                else { return }
                peripheral.writeValue(chunk, for: writeCharacteristic, type: .withoutResponse)
                controlPending.removeFirst(chunk.count)
            }
            return
        }
        guard isSending else { return }
        if transmission?.isComplete == true {
            deadline?.cancel()
            recovery?.cancel()
            recovery = nil
            transmission = nil
            pending.removeAll()
            isSending = false
            setStatus("设备已确认接收全部打印数据，纸张结果需人工确认")
            return
        }
        while peripheral.canSendWriteWithoutResponse {
            if pending.isEmpty {
                do {
                    guard recovery == nil else { return }
                    guard let packet = try transmission?.nextPacket() else {
                        if !waitingForAcknowledgement {
                            waitingForAcknowledgement = true
                            setStatus("已提交 \(totalBytes) 字节，等待打印机确认")
                        }
                        return
                    }
                    waitingForAcknowledgement = false
                    pending = packet
                } catch {
                    disconnect()
                    sendError = ServiceError("bitmap_read_failed", "读取位图失败，结果不确定", status: 500)
                    return
                }
            }
            guard
                let chunk = flow.nextChunk(
                    from: pending, maximumLength: peripheral.maximumWriteValueLength(for: .withoutResponse))
            else { return }
            peripheral.writeValue(chunk, for: writeCharacteristic, type: .withoutResponse)
            pending.removeFirst(chunk.count)
        }
    }
}

extension BluetoothPrinter: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            setStatus("Mac 蓝牙已就绪")
            if scanRequested { beginScan() }
        case .unauthorized:
            stopScan()
            resetConnection()
            setStatus("蓝牙权限未允许：系统设置 → 隐私与安全性 → 蓝牙 → 咕咕打印服务")
        case .poweredOff:
            stopScan()
            resetConnection()
            setStatus("Mac 蓝牙已关闭，请在系统设置中开启")
        default:
            setStatus("蓝牙状态：\(central.state.rawValue)，请稍后重试")
        }
    }

    public func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any],
        rssi signal: NSNumber
    ) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.uppercased().contains("G4HD") else { return }
        guard !devices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) else { return }
        devices.append(Device(peripheral: peripheral, name: name, signal: signal.intValue))
        log("发现 \(name)，UUID \(peripheral.identifier)，RSSI \(signal)")
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        setStatus("蓝牙连接成功，正在发现打印服务…")
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        deadline?.cancel()
        resetConnection()
        setStatus("连接失败：\(error?.localizedDescription ?? "请重试")")
    }

    public func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        deadline?.cancel()
        resetConnection()
        setStatus("打印机已断开：\(error?.localizedDescription ?? "可以重新扫描连接")")
    }
}

extension BluetoothPrinter: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            setStatus("服务发现失败：\(error!.localizedDescription)")
            return
        }
        for service in peripheral.services ?? [] {
            log("服务 \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
        guard error == nil else {
            setStatus("特征发现失败：\(error!.localizedDescription)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            let id = characteristic.uuid.uuidString
            log("特征 \(id)，属性 \(characteristic.properties.rawValue)")
            if id == "FF02", characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
            }
            if ["FF01", "FF03"].contains(id), characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        checkReady()
    }

    public func peripheral(
        _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?
    ) {
        guard error == nil, characteristic.isNotifying else {
            setStatus("订阅 \(characteristic.uuid) 失败：\(error?.localizedDescription ?? "未启用")")
            return
        }
        subscribed.insert(characteristic.uuid.uuidString)
        log("已订阅 \(characteristic.uuid)")
        if characteristic.uuid == CBUUID(string: "FF03"), characteristic.properties.contains(.read) {
            peripheral.readValue(for: characteristic)
        }
        checkReady()
    }

    public func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        guard error == nil, let data = characteristic.value else {
            setStatus("蓝牙响应错误：\(error?.localizedDescription ?? "空响应")")
            return
        }
        log("RX \(characteristic.uuid): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        if characteristic.uuid == CBUUID(string: "FF01") {
            if let controlCommand {
                do {
                    for reply in try controlDecoder.receive(data)
                    where reply.command == controlCommand || (controlCommand == 2 && reply.command == 10) {
                        controlReply = reply
                    }
                } catch {
                    controlError = error as? ServiceError
                }
                return
            }
            onAcknowledgement?(data.map { String(format: "%02X", $0) }.joined())
            guard isSending, let transmission else { return }
            do {
                for sequence in try transmission.receive(data) {
                    pending.removeAll()
                    setStatus("设备请求从第 \(sequence + 1) 包续传，等待 1.5 秒后恢复")
                    recovery?.cancel()
                    recovery = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(1500))
                        guard !Task.isCancelled, let self, isSending else { return }
                        do {
                            try transmission.resume()
                            recovery = nil
                            drain()
                        } catch {
                            failTransmission(error)
                        }
                    }
                }
                drain()
            } catch {
                failTransmission(error)
            }
        }
        if characteristic.uuid == CBUUID(string: "FF03") {
            flow.receive(data)
            log("流控：MTU \(flow.printerMTU)，可发送 \(flow.credits) 包")
            drain()
        }
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { drain() }

    private func failTransmission(_ error: Error) {
        disconnect()
        sendError = error as? ServiceError ?? ServiceError("transmission_failed", "发送失败，可能部分出纸", status: 409)
        setStatus(sendError?.message ?? "发送失败，结果不确定")
    }
}
