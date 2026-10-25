import ArgumentParser
import Foundation
import MemobirdCore

struct Service: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [
        Install.self, Start.self, Stop.self, Status.self, Uninstall.self,
    ])
    struct Install: AsyncParsableCommand {
        @Option(help: "构建产物 MemobirdService.app 路径") var bundle: String?
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            var source =
                bundle.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
                .appendingPathComponent("MemobirdService.app")
            if bundle == nil, !FileManager.default.fileExists(atPath: source.path) { source = Installer.app }
            try Installer.install(source: source)
            try await Installer.waitUntilReady()
            try emit(JSON.encode(["status": "installed", "app": Installer.app.path]), json: options.json)
        }
    }
    struct Start: AsyncParsableCommand {
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try Installer.start()
            try await Installer.waitUntilReady()
            try emit(JSON.encode(["status": "starting"]), json: options.json)
        }
    }
    struct Stop: AsyncParsableCommand {
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try Installer.stop()
            try emit(JSON.encode(["status": "stopped"]), json: options.json)
        }
    }
    struct Status: AsyncParsableCommand {
        @OptionGroup var options: ClientOptions
        mutating func run() async throws { try await emit(options.client().request("/v1/status"), json: options.json) }
    }
    struct Uninstall: AsyncParsableCommand {
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try Installer.stop()
            for file in [Installer.agent, Installer.cli, Installer.app]
            where FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            try emit(JSON.encode(["status": "uninstalled", "data": "retained"]), json: options.json)
        }
    }
}

/// Installs into the current user's login session; data survives uninstall.
enum Installer {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var app: URL { home.appendingPathComponent("Applications/咕咕打印服务.app") }
    static var cli: URL { home.appendingPathComponent(".local/bin/memobird") }
    static var agent: URL { home.appendingPathComponent("Library/LaunchAgents/local.memobird.service.plist") }
    static var domain: String { "gui/\(getuid())" }
    static var label: String { domain + "/local.memobird.service" }
    static func install(source: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.appendingPathComponent("Contents/MacOS/咕咕打印服务").path) else {
            throw ServiceError("bundle_missing", "请指定有效的 --bundle MemobirdService.app")
        }
        try stop()
        let oldApp = home.appendingPathComponent("Applications/MemobirdService.app")
        if oldApp != source.standardizedFileURL, manager.fileExists(atPath: oldApp.path) {
            try manager.removeItem(at: oldApp)
        }
        try manager.createDirectory(at: app.deletingLastPathComponent(), withIntermediateDirectories: true)
        if source.standardizedFileURL != app.standardizedFileURL {
            if manager.fileExists(atPath: app.path) { try manager.removeItem(at: app) }
            try manager.copyItem(at: source, to: app)
        }
        try manager.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: cli.path) || (try? manager.destinationOfSymbolicLink(atPath: cli.path)) != nil {
            try manager.removeItem(at: cli)
        }
        try manager.createSymbolicLink(
            at: cli, withDestinationURL: app.appendingPathComponent("Contents/MacOS/memobird"))
        let root = ServicePaths.localRoot
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tokenFile = root.appendingPathComponent("token")
        if !manager.fileExists(atPath: tokenFile.path) {
            let token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
            try Data(token.utf8).write(to: tokenFile, options: .atomic)
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFile.path)
        let clientToken = home.appendingPathComponent(".config/memobird/token")
        try manager.createDirectory(
            at: clientToken.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try Data(contentsOf: tokenFile).write(to: clientToken, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: clientToken.path)
        try manager.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        let configuration: [String: Any] = [
            "Label": "local.memobird.service",
            "ProgramArguments": [app.appendingPathComponent("Contents/MacOS/咕咕打印服务").path],
            "AssociatedBundleIdentifiers": ["local.memobird.mac"], "RunAtLoad": true, "KeepAlive": true,
            "ThrottleInterval": 10, "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null",
        ]
        try PropertyListSerialization.data(fromPropertyList: configuration, format: .xml, options: 0).write(
            to: agent, options: .atomic)
        let skill = app.appendingPathComponent("Contents/Resources/skills/memobird-print")
        if manager.fileExists(atPath: skill.path) {
            let destination = home.appendingPathComponent(".codex/skills/memobird-print")
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            try manager.copyItem(at: skill, to: destination)
        }
        try start()
    }
    static func start() throws {
        guard FileManager.default.fileExists(atPath: agent.path) else {
            throw ServiceError("not_installed", "请先运行 service install")
        }
        if try run("/bin/launchctl", ["print", label]) != 0 {
            guard try run("/bin/launchctl", ["bootstrap", domain, agent.path]) == 0 else {
                throw ServiceError("launch_failed", "无法注册 LaunchAgent，请查看 launchctl print")
            }
        }
        _ = try run("/bin/launchctl", ["kickstart", label])
    }
    static func waitUntilReady() async throws {
        let token = try String(contentsOf: ServicePaths.localRoot.appendingPathComponent("token"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8765/v1/status")!)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 1
        for _ in 0..<100 {
            if let (_, response) = try? await URLSession.shared.data(for: request),
                (response as? HTTPURLResponse)?.statusCode == 200
            {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ServiceError("startup_timeout", "LaunchAgent 已注册，但 HTTP 服务未在 10 秒内就绪", status: 503, retryable: true)
    }
    static func stop() throws {
        _ = try run("/bin/launchctl", ["bootout", label])
        let pidFile = ServicePaths.localRoot.appendingPathComponent("service.pid")
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
            let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1
        else { return }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "comm="]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let executable = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let oldApp = home.appendingPathComponent("Applications/MemobirdService.app")
        guard
            [app, oldApp].contains(where: { bundle in
                ["MemobirdService", "咕咕打印服务"].contains(where: {
                    executable == bundle.appendingPathComponent("Contents/MacOS/" + $0).path
                })
            })
        else { return }
        kill(pid, SIGTERM)
        for _ in 0..<50 {
            if kill(pid, 0) != 0 { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        if kill(pid, 0) == 0 { throw ServiceError("stop_timeout", "服务尚未退出，请稍后重试", status: 503) }
    }
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
