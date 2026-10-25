import ArgumentParser
import Foundation
import MemobirdCore

struct Memobird: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memobird", abstract: "无需 AppKey 的 MEMOBIRD 蓝牙打印服务", version: "1.0.0",
        subcommands: [
            Service.self, Printers.self, Printer.self, Render.self, Print.self, Jobs.self, Fonts.self, Logs.self,
            Paths.self,
        ])
}

struct Render: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [
        RenderMarkdown.self, RenderHTML.self, RenderImage.self,
    ])
}
struct Print: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "print", subcommands: [PrintMarkdown.self, PrintHTML.self, PrintImage.self, PrintRendered.self])
}
struct RenderMarkdown: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "markdown")
    @OptionGroup var options: DocumentOptions
    mutating func run() async throws { try await options.submit(kind: .markdown, mode: "render") }
}
struct RenderHTML: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "html")
    @OptionGroup var options: DocumentOptions
    mutating func run() async throws { try await options.submit(kind: .html, mode: "render") }
}
struct RenderImage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "image")
    @OptionGroup var options: DocumentOptions
    mutating func run() async throws { try await options.submit(kind: .image, mode: "render") }
}
struct PrintMarkdown: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "markdown")
    @OptionGroup var options: DocumentOptions
    mutating func run() async throws { try await options.submit(kind: .markdown, mode: "print") }
}
struct PrintHTML: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "html")
    @OptionGroup var options: DocumentOptions
    mutating func run() async throws { try await options.submit(kind: .html, mode: "print") }
}
struct PrintImage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "image")
    @OptionGroup var options: DocumentOptions
    mutating func run() async throws { try await options.submit(kind: .image, mode: "print") }
}
struct PrintRendered: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rendered")
    @Argument var id: String
    @Option(name: .customLong("idempotency-key")) var key: String?
    @Flag var wait = false
    @OptionGroup var options: ClientOptions
    mutating func run() async throws {
        let client = try options.client()
        let data = try await client.request(
            "/v1/jobs", method: "POST", body: JSON.encode(PrintRequest(renderId: id)), key: key ?? UUID().uuidString)
        let job = try JSON.decode(Job.self, from: data)
        try emit(wait ? try await client.wait(job.id) : data, json: options.json)
    }
}
struct Printers: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [Scan.self])
    struct Scan: AsyncParsableCommand {
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try await emit(options.client().request("/v1/printers/scan", method: "POST"), json: options.json)
        }
    }
}
struct Printer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [
        Connect.self, Status.self, Disconnect.self, Power.self, AutoOff.self,
    ])
    struct Power: AsyncParsableCommand {
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try await emit(options.client().request("/v1/printer/power"), json: options.json)
        }
    }
    struct AutoOff: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "auto-off")
        @Option(help: "0 关闭自动关机；1–255 为分钟数") var minutes: Int
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            _ = try PrinterPowerProtocol.setAutoOff(minutes: minutes)
            try await emit(
                options.client().request(
                    "/v1/printer/auto-off", method: "POST", body: JSON.encode(["minutes": minutes])),
                json: options.json)
        }
    }
    struct Connect: AsyncParsableCommand {
        @Option var id: String?
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try await emit(
                options.client().request(
                    "/v1/printer/connect", method: "POST", body: JSON.encode(id.map { ["id": $0] } ?? [:])),
                json: options.json)
        }
    }
    struct Status: AsyncParsableCommand {
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try await emit(options.client().request("/v1/printers"), json: options.json)
        }
    }
    struct Disconnect: AsyncParsableCommand {
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try await emit(options.client().request("/v1/printer/disconnect", method: "POST"), json: options.json)
        }
    }
}
struct Jobs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [
        List.self, Get.self, Cancel.self, Artifact.self, Purge.self,
    ])
    struct List: AsyncParsableCommand {
        @Option var limit: Int = 200
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try await emit(options.client().request("/v1/jobs?limit=\(limit)"), json: options.json)
        }
    }
    struct Get: AsyncParsableCommand {
        @Argument var id: String
        @Flag var wait = false
        @Option var timeout: Double = 300
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            let client = try options.client()
            let data = wait ? try await client.wait(id, timeout: timeout) : try await client.request("/v1/jobs/" + id)
            try emit(data, json: options.json)
        }
    }
    struct Cancel: AsyncParsableCommand {
        @Argument var id: String
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try await emit(options.client().request("/v1/jobs/\(id)/cancel", method: "POST"), json: options.json)
        }
    }
    struct Purge: AsyncParsableCommand {
        @Argument var id: String
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try await emit(options.client().request("/v1/jobs/\(id)/purge", method: "POST"), json: options.json)
        }
    }
    struct Artifact: AsyncParsableCommand {
        @Argument var id: String
        @Argument var name: String
        @Option var output: String
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try ResourceAsset.validatePath(name)
            guard !name.contains("/") else { throw ValidationError("文件名无效") }
            let data = try await options.client().request("/v1/jobs/\(id)/artifacts/\(name)")
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
            try emit(JSON.encode(["output": URL(fileURLWithPath: output).path]), json: options.json)
        }
    }
}
struct Fonts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [List.self, Add.self, Remove.self])
    struct List: AsyncParsableCommand {
        @OptionGroup var options: ClientOptions
        mutating func run() async throws { try await emit(options.client().request("/v1/fonts"), json: options.json) }
    }
    struct Add: AsyncParsableCommand {
        @Argument var file: String
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            let url = URL(fileURLWithPath: file)
            let asset = ResourceAsset(path: url.lastPathComponent, data: try Data(contentsOf: url))
            try await emit(
                options.client().request("/v1/fonts", method: "POST", body: JSON.encode(asset)), json: options.json)
        }
    }
    struct Remove: AsyncParsableCommand {
        @Argument var id: String
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try ResourceAsset.validatePath(id)
            guard !id.contains("/") else { throw ValidationError("字体 ID 无效") }
            try await emit(options.client().request("/v1/fonts/" + id, method: "DELETE"), json: options.json)
        }
    }
}
struct Logs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [Tail.self, Export.self, Prune.self])
    struct Filters: ParsableArguments {
        @Option var job: String?
        @Option var level: String?
        @Option var since: String?
        @Option var limit: Int = 2000
        @OptionGroup var options: ClientOptions
        var path: String {
            var components = URLComponents()
            components.path = "/v1/logs"
            components.queryItems = [("job", job), ("level", level), ("since", since), ("limit", String(limit))]
                .compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
            return components.string!
        }
    }
    struct Export: AsyncParsableCommand {
        @OptionGroup var filters: Filters
        mutating func run() async throws {
            try await emit(filters.options.client().request(filters.path), json: filters.options.json)
        }
    }
    struct Tail: AsyncParsableCommand {
        @OptionGroup var filters: Filters
        @Flag var follow = false
        mutating func run() async throws {
            var seen = Set<String>()
            repeat {
                let data = try await filters.options.client().request(filters.path)
                let events = try JSON.decode([LogEvent].self, from: data)
                for event in events {
                    let encoded = try JSON.encode(event)
                    if seen.insert(event.id).inserted { try emit(encoded, json: filters.options.json) }
                }
                if let last = events.last {
                    filters.since = ISO8601DateFormatter().string(from: last.time)
                    seen = Set(events.filter { $0.time == last.time }.map { $0.id })
                }
                if follow { try await Task.sleep(for: .seconds(2)) }
            } while follow
        }
    }
    struct Prune: AsyncParsableCommand {
        @OptionGroup var options: ClientOptions
        mutating func run() async throws {
            try await emit(options.client().request("/v1/maintenance/prune", method: "POST"), json: options.json)
        }
    }
}
struct Paths: AsyncParsableCommand {
    @OptionGroup var options: ClientOptions
    mutating func run() async throws { try await emit(options.client().request("/v1/paths"), json: options.json) }
}

@main
struct CommandMain {
    static func main() async {
        do {
            var command = try Memobird.parseAsRoot()
            if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            if CommandLine.arguments.contains("--json"), Memobird.exitCode(for: error) != .success {
                let failure = error as? ServiceError ?? ServiceError("cli_error", Memobird.message(for: error))
                if let data = try? JSON.encode(["error": failure]) {
                    try? FileHandle.standardError.write(contentsOf: data + Data([10]))
                }
                Foundation.exit(1)
            }
            Memobird.exit(withError: error)
        }
    }
}
