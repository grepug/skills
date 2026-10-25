import Foundation

public struct LogEvent: Codable, Sendable {
    public var id: String
    public init(time: Date, level: String, event: String, jobId: String?, message: String) {
        id = UUID().uuidString
        self.time = time
        self.level = level
        self.event = event
        self.jobId = jobId
        self.message = message
    }
    private enum CodingKeys: String, CodingKey { case id, time, level, event, jobId, message }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decode(Date.self, forKey: .time)
        level = try c.decode(String.self, forKey: .level)
        event = try c.decode(String.self, forKey: .event)
        jobId = try c.decodeIfPresent(String.self, forKey: .jobId)
        message = try c.decode(String.self, forKey: .message)
        id =
            try c.decodeIfPresent(String.self, forKey: .id)
            ?? JSON.fingerprint(Data("\(time)\(level)\(event)\(jobId ?? "")\(message)".utf8))
    }
    public var time: Date
    public var level: String
    public var event: String
    public var jobId: String?
    public var message: String
}

/// Append-only JSONL with bounded rotation; callers never pass content or credentials.
public final class EventLog: @unchecked Sendable {
    private let root: URL
    private let maximumBytes: Int
    private let maximumFiles: Int
    private let lock = NSRecursiveLock()
    public init(root: URL, maximumBytes: Int = 10_000_000, maximumFiles: Int = 10) throws {
        self.root = root
        self.maximumBytes = maximumBytes
        self.maximumFiles = maximumFiles
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public func write(level: String, event: String, jobId: String? = nil, message: String) throws {
        try lock.withLock {
            let url = root.appendingPathComponent("events.jsonl")
            let data =
                try JSON.encode(LogEvent(time: Date(), level: level, event: event, jobId: jobId, message: message))
                + Data([10])
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size + data.count > maximumBytes {
                for index in stride(from: maximumFiles - 1, through: 1, by: -1) {
                    let destination = root.appendingPathComponent("events.\(index).jsonl")
                    let source = root.appendingPathComponent(index == 1 ? "events.jsonl" : "events.\(index - 1).jsonl")
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    if FileManager.default.fileExists(atPath: source.path) {
                        try FileManager.default.moveItem(at: source, to: destination)
                    }
                }
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }
    }
    public func read(jobId: String?, level: String?, since: Date?, limit: Int = 2000) throws -> [LogEvent] {
        try lock.withLock {
            var events: [LogEvent] = []
            let count = max(0, min(limit, 10000))
            guard count > 0 else { return [] }
            // Rotation suffix records age; prune rewrites mtimes, so those cannot order files.
            let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "jsonl" }
                .sorted {
                    (Int($0.deletingPathExtension().pathExtension) ?? 0)
                        > (Int($1.deletingPathExtension().pathExtension) ?? 0)
                }
            for file in files {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var pending = Data()
                while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 10) {
                        let line = Data(pending[..<newline])
                        pending.removeSubrange(...newline)
                        guard let item = try? JSON.decode(LogEvent.self, from: line),
                            jobId == nil || item.jobId == jobId, level == nil || item.level == level,
                            since == nil || item.time >= since!
                        else { continue }
                        events.append(item)
                        if events.count > count + 100 { events.removeFirst(events.count - count) }
                    }
                    if pending.count > 1_000_000 { pending.removeAll() }
                }
            }
            return Array(events.suffix(count))
        }
    }
    public func prune(before: Date) throws {
        try lock.withLock {
            for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where file.pathExtension == "jsonl" {
                let lines = try Data(contentsOf: file).split(separator: 10).filter {
                    guard let event = try? JSON.decode(LogEvent.self, from: Data($0)) else { return false }
                    return event.time >= before
                }
                if lines.isEmpty {
                    try FileManager.default.removeItem(at: file)
                } else {
                    try lines.reduce(into: Data()) {
                        $0.append($1)
                        $0.append(10)
                    }.write(to: file, options: .atomic)
                }
            }
        }
    }
}
