import AppKit
import Darwin
import Hummingbird
import Logging
import MemobirdCore
import NIOPosix

@main
@MainActor
struct ServiceMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            var coordinator: PrintCoordinator?
            do {
                let root: URL
                if let override = ProcessInfo.processInfo.environment["MEMOBIRD_DATA_DIR"] {
                    root = URL(fileURLWithPath: override)
                } else {
                    root = URL.applicationSupportDirectory.appendingPathComponent("MemobirdService")
                }
                try FileManager.default.createDirectory(
                    at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let lockFile = root.appendingPathComponent("service.lock")
                let lockDescriptor = open(lockFile.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
                guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                    throw ServiceError("already_running", "已有咕咕打印服务使用此数据目录", status: 409)
                }
                defer { close(lockDescriptor) }
                let token = try String(contentsOf: root.appendingPathComponent("token"), encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard token.utf8.count >= 32 else {
                    throw ServiceError("configuration", "令牌不存在或过短；请运行 memobird service install")
                }
                let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
                let renderer = executable.deletingLastPathComponent().appendingPathComponent("MemobirdRenderer")
                try String(getpid()).write(
                    to: root.appendingPathComponent("service.pid"), atomically: true, encoding: .utf8)
                let service = try PrintCoordinator(root: root, rendererURL: renderer)
                coordinator = service
                // One I/O thread is sufficient for one printer and bounds idle thread overhead.
                let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
                let host = ProcessInfo.processInfo.environment["MEMOBIRD_HOST"] ?? "0.0.0.0"
                let port = Int(ProcessInfo.processInfo.environment["MEMOBIRD_PORT"] ?? "8765") ?? 8765
                let api = HTTPAPI(coordinator: service, token: token)
                var logger = Logger(label: "memobird.http")
                logger.logLevel = .error
                let server = Application(
                    responder: api, configuration: .init(address: .hostname(host, port: port)),
                    eventLoopGroupProvider: .shared(group), logger: logger)
                try await server.runService()
                await service.shutdown()
                try? FileManager.default.removeItem(at: root.appendingPathComponent("service.pid"))
                try await group.shutdownGracefully()
                exit(0)
            } catch {
                await coordinator?.shutdown()
                NSLog("Memobird service failed: %@", error.localizedDescription)
                exit(1)
            }
        }
        app.run()
    }
}
