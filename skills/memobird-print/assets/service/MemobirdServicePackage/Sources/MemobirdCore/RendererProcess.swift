import Foundation

/// Supervises one short-lived renderer; stdout contains only its small result envelope.
@MainActor
public final class RendererProcess {
    private let executable: URL
    private let timeout: TimeInterval
    private var process: Process?
    public var processId: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }
    public init(executable: URL, timeout: TimeInterval = 60) {
        self.executable = executable
        self.timeout = timeout
    }
    public func render(_ input: WorkerInput) async throws -> RenderArtifacts {
        guard process == nil else { throw ServiceError("renderer_busy", "渲染器正忙", status: 409) }
        let directory = URL(fileURLWithPath: input.directory)
        let inputFile = directory.appendingPathComponent("worker-input.json")
        try JSON.encode(input).write(to: inputFile, options: .atomic)
        let child = Process()
        let output = Pipe()
        child.executableURL = executable
        child.arguments = [inputFile.path]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        // Framework diagnostics are retained with the task, never mixed with JSON stdout.
        let diagnostics = directory.appendingPathComponent("renderer.log")
        FileManager.default.createFile(atPath: diagnostics.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let errorHandle = try FileHandle(forWritingTo: diagnostics)
        child.standardError = errorHandle
        process = child
        defer {
            process = nil
            try? errorHandle.close()
            try? output.fileHandleForReading.close()
            try? FileManager.default.removeItem(at: inputFile)
        }
        do {
            try child.run()
            let deadline = Date().addingTimeInterval(timeout)
            while child.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw ServiceError("render_timeout", "渲染进程超过时间限制", status: 422) }
                try await Task.sleep(for: .milliseconds(50))
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard data.count <= 65536 else { throw ServiceError("renderer_protocol", "渲染结果异常", status: 500) }
            let result = try JSON.decode(WorkerOutput.self, from: data)
            if let error = result.error { throw error }
            guard child.terminationStatus == 0, let artifacts = result.artifacts, !artifacts.bitmaps.isEmpty else {
                throw ServiceError("renderer_failed", "渲染进程异常退出", status: 422)
            }
            for name in artifacts.bitmaps + [artifacts.pdf].compactMap({ $0 }) { try ResourceAsset.validatePath(name) }
            return artifacts
        } catch {
            await stop()
            throw error
        }
    }
    public func stop() async {
        guard let process, process.isRunning else { return }
        process.terminate()
        for _ in 0..<20 where process.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        while process.isRunning { try? await Task.sleep(for: .milliseconds(20)) }
    }
}
