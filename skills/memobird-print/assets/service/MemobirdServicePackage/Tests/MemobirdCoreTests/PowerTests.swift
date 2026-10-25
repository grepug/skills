import Foundation
import Testing

@testable import MemobirdCore

struct PowerTests {
    @Test func autoOffZeroUsesSDKSettingCommandWithoutPrinting() throws {
        #expect(PrinterPowerProtocol.query == Data([0xAA, 1, 0, 2, 0x53]))
        #expect(try PrinterPowerProtocol.setAutoOff(minutes: 0) == Data([0xAA, 5, 0, 3, 19, 1, 0, 0, 0x3A]))
        #expect(try PrinterPowerProtocol.setAutoOff(minutes: 30) == Data([0xAA, 5, 0, 3, 19, 1, 0, 30, 0x1C]))
        #expect(throws: ServiceError.self) { try PrinterPowerProtocol.setAutoOff(minutes: -1) }
        #expect(throws: ServiceError.self) { try PrinterPowerProtocol.setAutoOff(minutes: 256) }
    }

    @Test(arguments: [
        Data([0xAA, 5, 0, 2, 19, 1, 0, 30, 0x1D]),
        Data([0xAA, 5, 0, 10, 19, 1, 0, 30, 0x15]),
    ])
    func powerReadbackRequiresValidCompleteInfoReply(reply: Data) throws {
        var decoder = PrinterReplyDecoder()
        #expect(try decoder.receive(reply.prefix(4)).isEmpty)
        let response = try #require(try decoder.receive(reply.dropFirst(4)).first)
        #expect(response.command == reply[3])
        #expect(try PrinterPowerProtocol.autoOffMinutes(in: response) == 30)
        var damaged = reply
        damaged[8] ^= 1
        #expect(try decoder.receive(damaged).isEmpty)
        let combined = try decoder.receive(reply + Data([0xAA, 5, 0, 10, 19, 1, 0, 0, 0x33]))
        #expect(combined.count == 2)
        #expect(try PrinterPowerProtocol.autoOffMinutes(in: combined[1]) == 0)
    }

    @Test func unrelatedOrMalformedReplyCannotClaimAutoOffDisabled() throws {
        var decoder = PrinterReplyDecoder()
        let wrongCommand = try #require(try decoder.receive(Data([0xAA, 5, 0, 3, 19, 1, 0, 0, 0x3A])).first)
        #expect(throws: ServiceError.self) { try PrinterPowerProtocol.autoOffMinutes(in: wrongCommand) }
        let missing = try #require(try decoder.receive(Data([0xAA, 1, 0, 10, 0x4B])).first)
        #expect(throws: ServiceError.self) { try PrinterPowerProtocol.autoOffMinutes(in: missing) }
        let malformed = PrinterProtocol.frame(command: 10, body: [19, 2, 0, 0])
        #expect(try decoder.receive(malformed).isEmpty)
    }
}
