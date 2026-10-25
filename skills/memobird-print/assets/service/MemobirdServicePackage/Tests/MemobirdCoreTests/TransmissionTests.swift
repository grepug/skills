import Foundation
import Testing

@testable import MemobirdCore

struct TransmissionTests {
    private let lostAfterNine = Data([
        0xAA, 0x13, 0, 4, 11, 2, 0, 0, 0, 12, 2, 0, 9, 0, 14, 1, 0, 0, 6, 1, 0, 0, 5,
    ])

    @Test func capturedPartialPrintResumesAfterNineWithoutReplayingAcceptedPackets() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("stripe.bmp")
        try Data(repeating: 0x5A, count: 60_830).write(to: file)
        let transmission = try PrintTransmission(files: [file])
        for _ in 0..<12 { _ = try #require(try transmission.nextPacket()) }
        let resumes = try transmission.receive(lostAfterNine)
        #expect(resumes == [9])
        #expect(!transmission.isComplete)
        #expect(try transmission.nextPacket() == nil)
        try transmission.resume()
        let resumed = try #require(try transmission.nextPacket())
        #expect(Array(resumed[7...8]) == [33, 0])
        #expect(Array(resumed[12...13]) == [10, 0])
        #expect(resumed.dropFirst(17).dropLast() == Data(repeating: 0x5A, count: 1900))
    }

    @Test func submittingAllBytesWaitsForFinalPrinterAcknowledgement() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("stripe.bmp")
        try Data(repeating: 0x5A, count: 60_830).write(to: file)
        let transmission = try PrintTransmission(files: [file])
        while try transmission.nextPacket() != nil {}
        #expect(!transmission.isComplete)
        _ = try transmission.receive(reply(count: 33, sequence: 33, result: 1))
        #expect(transmission.isComplete)
    }

    @Test func fragmentedAndCoalescedResponsesCannotFinishTheWrongJob() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("stripe.bmp")
        try Data(repeating: 0, count: 2000).write(to: file)
        let transmission = try PrintTransmission(files: [file])
        while try transmission.nextPacket() != nil {}
        var damaged = reply(count: 2, sequence: 2, result: 1)
        damaged[damaged.count - 1] ^= 1
        _ = try transmission.receive(damaged + reply(count: 10, sequence: 10, result: 1))
        #expect(!transmission.isComplete)
        let final = reply(count: 2, sequence: 2, result: 1)
        _ = try transmission.receive(final.prefix(8))
        #expect(!transmission.isComplete)
        _ = try transmission.receive(final.dropFirst(8))
        #expect(transmission.isComplete)
    }

    @Test func resumingAcrossBitmapStripesKeepsDocumentSequence() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.bmp")
        let second = root.appendingPathComponent("second.bmp")
        try Data(repeating: 1, count: 2000).write(to: first)
        try Data(repeating: 2, count: 2000).write(to: second)
        let transmission = try PrintTransmission(files: [first, second])
        while try transmission.nextPacket() != nil {}
        #expect(try transmission.receive(reply(count: 0, sequence: 2, result: 0)) == [2])
        try transmission.resume()
        let packet = try #require(try transmission.nextPacket())
        #expect(Array(packet[12...13]) == [3, 0])
        #expect(packet[17] == 2)
    }

    @Test func paperErrorsAndRepeatedLossStopInsteadOfReportingSuccess() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("stripe.bmp")
        try Data(repeating: 0, count: 2000).write(to: file)
        let transmission = try PrintTransmission(files: [file])
        _ = try transmission.nextPacket()
        #expect(throws: ServiceError.self) {
            try transmission.receive(reply(count: 0, sequence: 1, result: 0, status: 1))
        }
        let retrying = try PrintTransmission(files: [file])
        for _ in 0..<3 {
            while try retrying.nextPacket() != nil {}
            #expect(try retrying.receive(reply(count: 0, sequence: 1, result: 0)) == [1])
            try retrying.resume()
        }
        while try retrying.nextPacket() != nil {}
        #expect(throws: ServiceError.self) {
            try retrying.receive(reply(count: 0, sequence: 1, result: 0))
        }
        #expect(!retrying.isComplete)
    }

    private func reply(count: Int, sequence: Int, result: UInt8, status: UInt8 = 0) -> Data {
        PrinterProtocol.frame(
            command: 4,
            body: [
                11, 2, 0, UInt8(count), 0, 12, 2, 0, UInt8(sequence), 0,
                14, 1, 0, result, 6, 1, 0, status,
            ])
    }
}
