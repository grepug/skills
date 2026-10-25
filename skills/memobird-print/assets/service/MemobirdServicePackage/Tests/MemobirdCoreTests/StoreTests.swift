import Foundation
import Testing

@testable import MemobirdCore

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func idempotencySurvivesRestartAndRejectsChangedContent() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let input = PrintRequest(document: DocumentInput(kind: .markdown, content: "你好"))
    let first = try JobStore(root: root).submit(input, key: "one")
    let store = try JobStore(root: root)
    #expect(try store.submit(input, key: "one").id == first.id)
    #expect(try store.list().count == 1)
    #expect(throws: ServiceError.self) {
        try store.submit(PrintRequest(document: DocumentInput(kind: .markdown, content: "changed")), key: "one")
    }
}

@Test func interruptedTransmissionIsNeverAutomaticallyRequeued() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try JobStore(root: root)
    let sent = try store.submit(PrintRequest(document: DocumentInput(kind: .markdown, content: "test")), key: nil)
    let waiting = try store.submit(PrintRequest(document: DocumentInput(kind: .markdown, content: "next")), key: nil)
    try store.update(sent.id, state: .sending)
    try store.update(waiting.id, state: .rendering)
    try store.recover()
    #expect(try store.get(sent.id).state == .uncertain)
    #expect(try store.get(waiting.id).state == .queued)
    #expect(try store.hasUncertain())
}

@Test func rejectsPathsThatEscapeTaskResources() throws {
    for path in ["../secret", "/etc/passwd", "a/../../secret", "a\\b", "%2e%2e/secret", ".", ""] {
        #expect(throws: ServiceError.self) { try ResourceAsset.validatePath(path) }
    }
    try ResourceAsset.validatePath("images/猫.png")
}

@Test func rotationAndRetentionKeepActiveTasks() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try JobStore(root: root)
    let active = try store.submit(PrintRequest(document: DocumentInput(kind: .markdown, content: "active")), key: nil)
    let old = try store.submit(PrintRequest(document: DocumentInput(kind: .markdown, content: "old")), key: nil)
    try store.update(old.id, state: .transmitted)
    try store.prune(now: Date().addingTimeInterval(8 * 86400))
    #expect(FileManager.default.fileExists(atPath: store.directory(active.id).path))
    #expect(!FileManager.default.fileExists(atPath: store.directory(old.id).path))
    #expect(try store.get(old.id).state == .transmitted)
    let log = try EventLog(root: root.appendingPathComponent("logs"), maximumBytes: 200, maximumFiles: 3)
    for i in 0..<30 { try log.write(level: "info", event: "test", jobId: "j", message: "message \(i)") }
    let files = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("logs").path)
    #expect(files.count <= 3)
    #expect(try log.read(jobId: "j", level: "info", since: nil).count > 0)
    try log.prune(before: Date().addingTimeInterval(1))
    #expect(try log.read(jobId: nil, level: nil, since: nil).isEmpty)
}

@Test func streamedPacketsKeepGlobalSequenceAcrossBitmapFiles() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(repeating: 0x55, count: 1901).write(to: root.appendingPathComponent("one.bmp"))
    try Data([0x33]).write(to: root.appendingPathComponent("two.bmp"))
    let stream = try BitmapPacketStream(files: [
        root.appendingPathComponent("one.bmp"), root.appendingPathComponent("two.bmp"),
    ])
    var packets: [Data] = []
    while let packet = try stream.next() { packets.append(packet) }
    #expect(packets.count == 3)
    #expect(Array(packets[2].prefix(14)) == [0xaa, 0x0f, 0, 4, 11, 2, 0, 3, 0, 12, 2, 0, 3, 0])
    #expect(packets.allSatisfy { $0.reduce(UInt8(0), &+) == 0 })
}

@MainActor
@Test func stalledRendererTimesOutAndIsReaped() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let helper = root.appendingPathComponent("helper")
    try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: helper, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let runner = RendererProcess(executable: helper, timeout: 0.2)
    let input = WorkerInput(
        directory: root.path, fontsDirectory: root.path, document: DocumentInput(kind: .markdown, content: "x"))
    await #expect(throws: ServiceError.self) { try await runner.render(input) }
    #expect(runner.processId == nil)
}

@Test func logCursorDoesNotLoseEventsWithTheSameTimestamp() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let log = try EventLog(root: root)
    try log.write(level: "info", event: "one", message: "first")
    let cursor = try #require(log.read(jobId: nil, level: nil, since: nil).last).time
    try log.write(level: "info", event: "two", message: "second")
    let events = try log.read(jobId: nil, level: nil, since: cursor)
    #expect(events.contains { $0.event == "two" })
}

@Test func concurrentIdempotentSubmissionsCreateOneDurableTask() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try JobStore(root: root)
    let input = PrintRequest(document: DocumentInput(kind: .markdown, content: "one"))
    let ids = try await withThrowingTaskGroup(of: String.self) { group in
        for _ in 0..<20 { group.addTask { try store.submit(input, key: "shared").id } }
        var ids = Set<String>()
        for try await id in group { ids.insert(id) }
        return ids
    }
    #expect(ids.count == 1)
    #expect(try store.list().count == 1)
}

@Test func retentionRemovesOldMetadataButKeepsUnresolvedUncertainty() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try JobStore(root: root)
    let old = try store.submit(PrintRequest(document: DocumentInput(kind: .markdown, content: "old")), key: nil)
    let uncertain = try store.submit(
        PrintRequest(document: DocumentInput(kind: .markdown, content: "uncertain")), key: nil)
    try store.update(old.id, state: .failed)
    try store.update(uncertain.id, state: .uncertain)
    try store.prune(now: Date().addingTimeInterval(31 * 86400))
    #expect(throws: ServiceError.self) { try store.get(old.id) }
    #expect(try store.hasUncertain())
    _ = try store.cancel(uncertain.id)
    #expect(try !store.hasUncertain())
}

@Test func quotaRejectionDoesNotLeaveAnUntrackedJobDirectory() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try JobStore(root: root, quota: 100)
    #expect(throws: ServiceError.self) {
        try store.submit(
            PrintRequest(document: DocumentInput(kind: .markdown, content: String(repeating: "x", count: 300))),
            key: nil)
    }
    #expect(try store.list().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("jobs").path).isEmpty)
}

@Test func manualArtifactPurgePreservesIdempotencyAndProtectsActiveTasks() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try JobStore(root: root)
    let input = PrintRequest(document: DocumentInput(kind: .markdown, content: "private"))
    let job = try store.submit(input, key: "purge-key")
    #expect(throws: ServiceError.self) { try store.purgeArtifacts(job.id) }
    try store.update(job.id, state: .transmitted)
    try store.purgeArtifacts(job.id)
    #expect(!FileManager.default.fileExists(atPath: store.directory(job.id).path))
    let retry = try store.submit(input, key: "purge-key")
    #expect(retry.id == job.id && retry.state == .transmitted && retry.artifactsExpired)
}

@Test func pruningDoesNotReorderRotatedLogsOrHideNewestEntries() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let log = try EventLog(root: root, maximumBytes: 400, maximumFiles: 4)
    for index in 0..<50 { try log.write(level: "info", event: "ordered", message: String(index)) }
    try log.prune(before: .distantPast)
    let latest = try log.read(jobId: nil, level: nil, since: nil, limit: 1)
    #expect(latest.last?.message == "49")
}
