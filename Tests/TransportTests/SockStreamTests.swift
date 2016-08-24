import Foundation
import XCTest

import Core
import SocksCore
@testable import Transport

class SockStreamTests: XCTestCase {
    static let allTests = [
        ("testTCPInternetSocket", testTCPInternetSocket),
        ("testTCPInternetSocketThrows", testTCPInternetSocketThrows),
        ("testTCPServer", testTCPServer),
        ("testSecurityLayerStrings", testSecurityLayerStrings),
        ("testFoundationStream", testFoundationStream),
        ("testFoundationThrows", testFoundationThrows),
        ("testFoundationEventCode", testFoundationEventCode)
    ]

    func testTCPInternetSocket() throws {
        // from SocksExampleTCPClient
        let stream = try TCPProgramStream(host: "google.com", port: 80)
        let sock = stream.stream
        try sock.setTimeout(10)
        try sock.connect()
        try sock.send("GET /\r\n\r\n".bytes)
        try sock.flush()
        let received = try sock.receive(max: 2048)
        try sock.close()

        // Receiving the raw google homepage
        XCTAssert(received.string.contains("<title>Google</title>"))
    }

    func testTCPInternetSocketThrows() throws {
        // from SocksExampleTCPClient
        let stream = try TCPProgramStream(host: "google.com", port: 80)
        let sock = stream.stream

        do {
            try sock.send("GET /\r\n\r\n".bytes)
            XCTFail("should throw -- not connected")
        } catch {}

        do {
            _ = try sock.receive(max: 2048)
            XCTFail("should throw -- not connected")
        } catch {}
    }

    func testTCPServer() throws {
        let serverStream = try TCPServerStream(host: "0.0.0.0", port: 2653)
        _ = try background {
            do {
                let connection = try serverStream.accept()
                let message = try connection.receive(max: 2048).string
                XCTAssert(message == "Hello, World!")
            } catch {
                XCTFail("failed w/ \(error)")
            }
        }

        let program = try TCPClientStream(host: "0.0.0.0", port: 2653)
        let sock = try program.connect()
        try sock.send("Hello, World!".bytes)
    }

    func testSecurityLayerStrings() {
        let schemes: [(String, SecurityLayer)] = [
            ("https", .tls),
            ("http", .none),
            ("wss", .tls),
            ("ws", .none)
        ]

        schemes.forEach { scheme, securityLayer in
            XCTAssert(scheme.securityLayer == securityLayer)
        }
    }

    func testFoundationStream() throws {
        #if !os(Linux)
            // will default to underlying FoundationStream for TLS.
            let clientStream = try FoundationStream(host: "google.com", port: 443, securityLayer: .tls)
            let connection = try clientStream.connect()
            XCTAssert(!connection.closed)
            do {
                try connection.setTimeout(30)
                XCTFail("Foundation stream should throw on timeout set")
            } catch {}
            try connection.send("GET / \r\n\r\n".bytes)
            try connection.flush()
            let received = try connection.receive(max: 2048)
            try connection.close()

            XCTAssert(connection.closed)
            // Receiving the raw google homepage
            XCTAssert(received.string.contains("<title>Google</title>"))
        #endif
    }

    func testFoundationThrows() throws {
        #if !os(Linux)
            // will default to underlying FoundationStream for TLS.
            let clientStream = try FoundationStream(host: "nothere", port: 9999)
            let connection = try clientStream.connect()
            // should skip empty buffer
            try connection.send([])

            do {
                try connection.send("hi".bytes)
                XCTFail("Foundation stream should throw on send not valid")
            } catch {}

            do {
                _ = try connection.receive(max: 2048)
                XCTFail("Foundation stream should throw on send not valid")
            } catch {}
        #endif
    }

    func testFoundationEventCode() throws {
        #if !os(Linux)
            // will default to underlying FoundationStream for TLS.
            let clientStream = try FoundationStream(host: "google.com", port: 443, securityLayer: .tls)
            let connection = try clientStream.connect()
            XCTAssertFalse(connection.closed)
            // Force Foundation.Stream delegate
            clientStream.stream(clientStream.input, handle: .endEncountered)
            XCTAssertTrue(connection.closed)
        #endif
    }
}
