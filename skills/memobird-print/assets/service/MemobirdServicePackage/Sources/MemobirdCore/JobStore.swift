import CSQLite
import Foundation

/// SQLite is accessed under one lock; content stays in private per-job directories.
public final class JobStore: @unchecked Sendable {
    public let root: URL
    private let lock = NSRecursiveLock()
    private var database: OpaquePointer?
    private let quota: Int64
    public init(root: URL, quota: Int64 = 2_000_000_000) throws {
        self.root = root
        self.quota = quota
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("jobs"), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        guard sqlite3_open(root.appendingPathComponent("jobs.sqlite").path, &database) == SQLITE_OK else {
            throw ServiceError("storage", "无法打开任务数据库", status: 500)
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        try execute(
            "CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, token TEXT UNIQUE, fingerprint TEXT NOT NULL, record BLOB NOT NULL)"
        )
    }
    deinit { sqlite3_close(database) }
    public func directory(_ id: String) -> URL { root.appendingPathComponent("jobs").appendingPathComponent(id) }

    public func submit(_ request: PrintRequest, key: String?, mode: String = "print") throws -> Job {
        try lock.withLock {
            guard (request.document != nil) != (request.renderId != nil), mode == "print" || mode == "render" else {
                throw ServiceError("invalid_request", "document 和 renderId 必须提供且只能提供一个")
            }
            if let key, key.isEmpty || key.utf8.count > 200 { throw ServiceError("invalid_key", "幂等键长度须为 1–200 字节") }
            try request.document?.validate()
            let input = try JSON.encode(request)
            let fingerprint = JSON.fingerprint(Data(mode.utf8) + input)
            if let key, let row = try query("SELECT fingerprint,record FROM jobs WHERE token=?", [key]).first {
                guard String(data: row[0], encoding: .utf8) == fingerprint else {
                    throw ServiceError("idempotency_conflict", "同一幂等键已用于不同内容", status: 409)
                }
                return try JSON.decode(Job.self, from: row[1])
            }
            var source: Job?
            if let renderId = request.renderId {
                source = try get(renderId)
                guard source?.artifacts != nil, source?.artifactsExpired == false, source?.state.terminal == true else {
                    throw ServiceError("render_unavailable", "引用任务没有可用的渲染结果", status: 409)
                }
            }
            guard try diskUsage() + Int64(input.count) < quota else {
                throw ServiceError("quota_exceeded", "任务存储已达到 2 GB 配额，请清理", status: 507)
            }
            var job = Job(id: UUID().uuidString.lowercased(), mode: mode)
            let directory = directory(job.id)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            do {
                try input.write(to: directory.appendingPathComponent("input.json"), options: .atomic)
                if let source, let artifacts = source.artifacts {
                    for name in artifacts.bitmaps + [artifacts.pdf].compactMap({ $0 }) {
                        try ResourceAsset.validatePath(name)
                        try FileManager.default.copyItem(
                            at: self.directory(source.id).appendingPathComponent(name),
                            to: directory.appendingPathComponent(name))
                    }
                    job.artifacts = artifacts
                }
                let record = try JSON.encode(job)
                try execute(
                    "INSERT INTO jobs(id,token,fingerprint,record) VALUES(?,?,?,?)",
                    [Data(job.id.utf8), key.map { Data($0.utf8) }, Data(fingerprint.utf8), record])
                return job
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
    }
    public func get(_ id: String) throws -> Job {
        try lock.withLock {
            guard UUID(uuidString: id) != nil,
                let data = try query("SELECT record FROM jobs WHERE id=?", [id]).first?.first
            else {
                throw ServiceError("job_not_found", "任务不存在", status: 404)
            }
            return try JSON.decode(Job.self, from: data)
        }
    }
    public func list() throws -> [Job] {
        try lock.withLock {
            try query("SELECT record FROM jobs ORDER BY rowid", []).map { try JSON.decode(Job.self, from: $0[0]) }
        }
    }
    public func request(_ id: String) throws -> PrintRequest {
        _ = try get(id)
        return try JSON.decode(
            PrintRequest.self, from: Data(contentsOf: directory(id).appendingPathComponent("input.json")))
    }
    public func update(
        _ id: String, state: JobState? = nil, artifacts: RenderArtifacts? = nil, error: ServiceError? = nil,
        acknowledgement: String? = nil
    ) throws {
        try lock.withLock {
            var job = try get(id)
            if let state { job.state = state }
            if let artifacts { job.artifacts = artifacts }
            if let acknowledgement { job.deviceAcknowledgement = acknowledgement }
            job.error = error
            job.updatedAt = Date()
            try save(job)
        }
    }
    public func recover() throws {
        try lock.withLock {
            for job in try list() {
                if job.state == .sending {
                    try update(
                        job.id, state: .uncertain,
                        error: ServiceError("interrupted", "发送期间服务退出，可能已经部分打印；请检查纸张", status: 409))
                } else if [.rendering, .waitingForPrinter].contains(job.state) {
                    try update(job.id, state: .queued)
                }
            }
        }
    }
    public func hasUncertain() throws -> Bool { try list().contains { $0.state == .uncertain } }
    public func cancel(_ id: String) throws -> Job {
        try lock.withLock {
            let job = try get(id)
            if job.state == .uncertain {
                try update(
                    id, state: .cancelled,
                    error: ServiceError("uncertain_acknowledged", "已确认不自动重印；纸上结果仍需人工判断", status: 409))
            } else if !job.state.terminal {
                try update(id, state: job.state == .sending ? .uncertain : .cancelled)
            }
            return try get(id)
        }
    }
    public func prune(now: Date = Date()) throws {
        try lock.withLock {
            for var job in try list() where job.state.terminal {
                if now.timeIntervalSince(job.updatedAt) > 7 * 86400, !job.artifactsExpired {
                    if FileManager.default.fileExists(atPath: directory(job.id).path) {
                        try FileManager.default.removeItem(at: directory(job.id))
                    }
                    job.artifactsExpired = true
                    try save(job)
                }
                // Unresolved uncertainty must survive cleanup to preserve the queue pause.
                if now.timeIntervalSince(job.updatedAt) > 30 * 86400, job.state != .uncertain {
                    try execute("DELETE FROM jobs WHERE id=?", [Data(job.id.utf8)])
                }
            }
        }
    }
    /// Removes only terminal task content; keeps history and idempotency to prevent reprints.
    public func purgeArtifacts(_ id: String) throws {
        try lock.withLock {
            var job = try get(id)
            guard job.state.terminal else { throw ServiceError("job_active", "活动任务不能清理，请先取消", status: 409) }
            if FileManager.default.fileExists(atPath: directory(id).path) {
                try FileManager.default.removeItem(at: directory(id))
            }
            job.artifactsExpired = true
            try save(job)
        }
    }
    public func diskUsage() throws -> Int64 {
        let enumerator = FileManager.default.enumerator(
            at: root.appendingPathComponent("jobs"), includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        var total: Int64 = 0
        guard let enumerator else { return 0 }
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
    private func save(_ job: Job) throws {
        try execute("UPDATE jobs SET record=? WHERE id=?", [try JSON.encode(job), Data(job.id.utf8)])
    }
    private func execute(_ sql: String, _ values: [Data?] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw storageError() }
    }
    private func query(_ sql: String, _ values: [String]) throws -> [[Data]] {
        let statement = try prepare(sql, values.map { Data($0.utf8) })
        defer { sqlite3_finalize(statement) }
        var rows: [[Data]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw storageError() }
            rows.append(
                (0..<sqlite3_column_count(statement)).map { index in
                    guard let bytes = sqlite3_column_blob(statement, index) else { return Data() }
                    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
                })
        }
    }
    private func prepare(_ sql: String, _ values: [Data?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw storageError()
        }
        for (index, value) in values.enumerated() {
            let result: Int32
            if let value {
                result = value.withUnsafeBytes {
                    sqlite3_bind_text(
                        statement, Int32(index + 1), $0.baseAddress?.assumingMemoryBound(to: CChar.self),
                        Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            } else {
                result = sqlite3_bind_null(statement, Int32(index + 1))
            }
            if result != SQLITE_OK {
                sqlite3_finalize(statement)
                throw storageError()
            }
        }
        return statement
    }
    private func storageError() -> ServiceError {
        ServiceError("storage", String(cString: sqlite3_errmsg(database)), status: 500)
    }
}
