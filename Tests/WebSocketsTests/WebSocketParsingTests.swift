import XCTest
import Foundation

import libc
import HTTP
import Core
import Transport
@testable import WebSockets
import Sockets


/*
    Examples from: https://tools.ietf.org/html/rfc6455#section-5.7

    o  A single-frame unmasked text message

    *  0x81 0x05 0x48 0x65 0x6c 0x6c 0x6f (contains "Hello")

    o  A single-frame masked text message

    *  0x81 0x85 0x37 0xfa 0x21 0x3d 0x7f 0x9f 0x4d 0x51 0x58
    (contains "Hello")

    o  A fragmented unmasked text message

    *  0x01 0x03 0x48 0x65 0x6c (contains "Hel")

    *  0x80 0x02 0x6c 0x6f (contains "lo")


    Fette & Melnikov             Standards Track                   [Page 38]

    RFC 6455                 The WebSocket Protocol            December 2011


    o  Unmasked Ping request and masked Ping response

    *  0x89 0x05 0x48 0x65 0x6c 0x6c 0x6f (contains a body of "Hello",
    but the contents of the body are arbitrary)

    *  0x8a 0x85 0x37 0xfa 0x21 0x3d 0x7f 0x9f 0x4d 0x51 0x58
    (contains a body of "Hello", matching the body of the ping)

    o  256 bytes binary message in a single unmasked frame

    *  0x82 0x7E 0x0100 [256 bytes of binary data]

    o  64KiB binary message in a single unmasked frame

    *  0x82 0x7F 0x0000000000010000 [65536 bytes of binary data]
*/
class WebSocketSerializationTests: XCTestCase {
    static let allTests = [
        ("testMaximumWebSocketFramePayloadBuffer", testMaximumWebSocketFramePayloadBuffer),
        ("testSingleFrameUnmaskedTextMessage", testSingleFrameUnmaskedTextMessage),
        ("testSingleFrameMaskedTextMessage", testSingleFrameMaskedTextMessage),
        ("testFragmentedUnmaskedTextMessageOne", testFragmentedUnmaskedTextMessageOne),
        ("testFragmentedUnmaskedTextMessageTwo", testFragmentedUnmaskedTextMessageTwo),
        ("testUnmaskedPingRequest", testUnmaskedPingRequest),
        ("testMaskedPongResponse", testMaskedPongResponse),
        ("test256BytesBinarySingleUnmaskedFrame", test256BytesBinarySingleUnmaskedFrame),
        ("testSixtyFourKiBSingleUnmaskedFrame", testSixtyFourKiBSingleUnmaskedFrame),
    ]
    
    func testMaximumWebSocketFramePayloadBuffer() throws {
        func testSuccess() throws {
            let input: [Byte] = [0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]
            
            let test = TestStream()
            _ = try test.write(input)
            
            let msg = try FrameParser(stream: test, maxSize: 10).acceptFrame()
            let str = msg.payload.makeString()
            XCTAssertEqual(str, "Hello")
        }
        
        func testBarelySuccess() throws {
            let input: [Byte] = [0x81, 0x0a, 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x48, 0x65, 0x6c, 0x6c, 0x6f]
            
            let test = TestStream()
            _ = try test.write(input)
            
            let msg = try FrameParser(stream: test, maxSize: 10).acceptFrame()
            let str = msg.payload.makeString()
            XCTAssertEqual(str, "HelloHello")
        }
        
        func testFailure() throws {
            let input: [Byte] = [0x81, 0x0b, 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x48]
            
            let test = TestStream()
            _ = try test.write(input)
            
            XCTAssertThrowsError(try FrameParser(stream: test, maxSize: 10).acceptFrame())
        }
        
        try testSuccess()
        try testBarelySuccess()
    }

    func testSingleFrameUnmaskedTextMessage() throws {
        let input: [Byte] = [0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]
        let test = TestStream()
        _ = try test.write(input)
        let msg = try FrameParser(stream: test, maxSize: 100_000).acceptFrame()
        let str = msg.payload.makeString()
        XCTAssert(str == "Hello")

        let header = msg.header
        XCTAssert(header.fin)
        XCTAssert(header.rsv1 == false)
        XCTAssert(header.rsv2 == false)
        XCTAssert(header.rsv3 == false)
        XCTAssert(header.isMasked == false)
        XCTAssert(header.opCode == .text)
        XCTAssert(header.payloadLength == 5)

        // Test return to bytes
        assertSerialized(msg, equals: input)
    }

    func testSingleFrameMaskedTextMessage() throws {
        let input: [Byte] = [0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]
        let test = TestStream()
        _ = try test.write(input)
        let msg = try FrameParser(stream: test, maxSize: 100_000).acceptFrame()
        let str = msg.payload.makeString()
        XCTAssert(str == "Hello")

        let header = msg.header
        XCTAssert(header.fin)
        XCTAssert(header.rsv1 == false)
        XCTAssert(header.rsv2 == false)
        XCTAssert(header.rsv3 == false)
        XCTAssert(header.isMasked == true)
        XCTAssert(header.opCode == .text)
        XCTAssert(header.payloadLength == 5)

        // Test return to bytes
        assertSerialized(msg, equals: input)
    }

    /*
        o  A fragmented unmasked text message

        *  0x01 0x03 0x48 0x65 0x6c (contains "Hel")

        *  0x80 0x02 0x6c 0x6f (contains "lo")
    */
    func testFragmentedUnmaskedTextMessageOne() throws {
        let input: [Byte] = [0x01, 0x03, 0x48, 0x65, 0x6c]
        let test = TestStream()
        _ = try test.write(input)
        let msg = try FrameParser(stream: test, maxSize: 100_000).acceptFrame()
        XCTAssert(msg.isFragment)
        XCTAssert(msg.isFragmentHeader)
        XCTAssertFalse(msg.isControlFrame)

        let str = msg.payload.makeString()
        XCTAssert(str == "Hel")

        let header = msg.header
        XCTAssert(header.fin == false)
        XCTAssert(header.rsv1 == false)
        XCTAssert(header.rsv2 == false)
        XCTAssert(header.rsv3 == false)
        XCTAssert(header.isMasked == false)
        XCTAssert(header.opCode == .text)
        XCTAssert(header.payloadLength == 3)

        // Test return to bytes
        assertSerialized(msg, equals: input)
    }

    func testFragmentedUnmaskedTextMessageTwo() throws {
        let input: [Byte] = [0x80, 0x02, 0x6c, 0x6f]
        let test = TestStream()
        _ = try test.write(input)
        let msg = try FrameParser(stream: test, maxSize: 100_000).acceptFrame()
        XCTAssert(msg.isFragment)
        XCTAssert(msg.isFragmentFooter)
        XCTAssertFalse(msg.isControlFrame)

        let str = msg.payload.makeString()
        XCTAssert(str == "lo")

        let header = msg.header
        XCTAssert(header.fin == true)
        XCTAssert(header.rsv1 == false)
        XCTAssert(header.rsv2 == false)
        XCTAssert(header.rsv3 == false)
        XCTAssert(header.isMasked == false)
        XCTAssert(header.opCode == .continuation)
        XCTAssert(header.payloadLength == 2)

        // Test return to bytes
        assertSerialized(msg, equals: input)
    }

    /*

     Unmasked Ping request and masked Ping response
     *  0x89 0x05 0x48 0x65 0x6c 0x6c 0x6f (contains a body of "Hello",
     but the contents of the body are arbitrary)

     *  0x8a 0x85 0x37 0xfa 0x21 0x3d 0x7f 0x9f 0x4d 0x51 0x58
     (contains a body of "Hello", matching the body of the ping)
     */
    func testUnmaskedPingRequest() throws {
        let input: [Byte] = [0x89, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]
        let test = TestStream()
        _ = try test.write(input)
        let msg = try FrameParser(stream: test, maxSize: 100_000).acceptFrame()
        XCTAssert(msg.isControlFrame)

        // is Hello, but message doesn't matter
        let str = msg.payload.makeString()
        XCTAssert(str == "Hello")

        let header = msg.header
        XCTAssert(header.fin == true)
        XCTAssert(header.rsv1 == false)
        XCTAssert(header.rsv2 == false)
        XCTAssert(header.rsv3 == false)
        XCTAssert(header.isMasked == false)
        XCTAssert(header.opCode == .ping)
        XCTAssert(header.payloadLength == 5)

        // Test return to bytes
        assertSerialized(msg, equals: input)
    }

    func testMaskedPongResponse() throws {
        /*
         Client to Server MUST be masked
         */
        let input: [Byte] = [0x8a, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]
        let test = TestStream()
        _ = try test.write(input)
        let msg = try FrameParser(stream: test, maxSize: 100_000).acceptFrame()
        XCTAssert(msg.isControlFrame)

        // is Hello, but message doesn't matter. Must match `ping` payload
        let str = msg.payload.makeString()
        XCTAssert(str == "Hello")

        let header = msg.header
        XCTAssert(header.fin == true)
        XCTAssert(header.rsv1 == false)
        XCTAssert(header.rsv2 == false)
        XCTAssert(header.rsv3 == false)
        XCTAssert(header.isMasked == true)
        XCTAssert(header.opCode == .pong)
        XCTAssert(header.payloadLength == 5)

        // Test return to bytes
        assertSerialized(msg, equals: input)
    }

    /*
     o  256 bytes binary message in a single unmasked frame

     *  0x82 0x7E 0x0100 [256 bytes of binary data]
     */
    func test256BytesBinarySingleUnmaskedFrame() throws {
        // ensure 16 bit lengths
        var randomBinary: [Byte] = []
        (1...256).forEach { _ in
            let random = UInt8.random()
            randomBinary.append(random)
        }

        // 256 as two UInt8
        let twoFiftySix: [Byte] = [0x01, 0x00]
        let headerBytes: [Byte] = [0x82, 0x7E] + twoFiftySix
        let input = headerBytes + randomBinary
        let test = TestStream()
        _ = try test.write(input)
        let msg = try FrameParser(stream: test, maxSize: 100_000).acceptFrame()
        XCTAssertFalse(msg.isControlFrame)

        let payload = msg.payload
        XCTAssert(payload == randomBinary)

        let header = msg.header
        XCTAssert(header.fin == true)
        XCTAssert(header.rsv1 == false)
        XCTAssert(header.rsv2 == false)
        XCTAssert(header.rsv3 == false)
        XCTAssert(header.isMasked == false)
        XCTAssert(header.opCode == .binary)
        XCTAssert(header.payloadLength == 256)

        // Test return to bytes
        assertSerialized(msg, equals: input)
    }

    /*
     If payload length is > can fit in 2 bytes, will become 8 byte length

     o  64KiB binary message in a single unmasked frame

     *  0x82 0x7F 0x0000000000010000 [65536 bytes of binary data]
     */
    func testSixtyFourKiBSingleUnmaskedFrame() throws {
        // ensure 64 bit lengths
        var randomBinary: [Byte] = []
        (1...65536).forEach { _ in
            let random = UInt8.random()
            randomBinary.append(random)
        }

        // 65536 as 8 UInt8
        let sixFiveFiveThreeSix: [Byte] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00]
        let headerBytes: [Byte] = [0x82, 0x7F] + sixFiveFiveThreeSix

        let input = headerBytes + randomBinary
        let test = TestStream()
        _ = try test.write(input)
        let msg = try FrameParser(stream: test, maxSize: 100_000).acceptFrame()
        XCTAssertFalse(msg.isControlFrame)

        let payload = msg.payload
        XCTAssert(payload == randomBinary)

        let header = msg.header
        XCTAssert(header.fin == true)
        XCTAssert(header.rsv1 == false)
        XCTAssert(header.rsv2 == false)
        XCTAssert(header.rsv3 == false)
        XCTAssert(header.isMasked == false)
        XCTAssert(header.opCode == .binary)
        XCTAssert(header.payloadLength == 65536)

        // Test return to bytes
        assertSerialized(msg, equals: input)
    }

    private func assertSerialized(_ frame: WebSocket.Frame, equals bytes: [Byte], caller: String = #function) {
        let serializer = FrameSerializer(frame)
        let serialized = serializer.serialize()

        XCTAssertEqual(serialized, bytes, caller)
    }
}

class WebSocketKeyTests: XCTestCase {
    static var allTests: [(String, (WebSocketKeyTests) -> () throws -> Void)] {
        return [
            ("testExchangeKey", testExchangeKey)
        ]
    }

    /*
        https://tools.ietf.org/html/rfc6455#section-1.3

        Concretely, if as in the example above, the |Sec-WebSocket-Key|
        header field had the value "dGhlIHNhbXBsZSBub25jZQ==", the server
        would concatenate the string "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        to form the string "dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-
        C5AB0DC85B11".  The server would then take the SHA-1 hash of this,
        giving the value 0xb3 0x7a 0x4f 0x2c 0xc0 0x62 0x4f 0x16 0x90 0xf6
        0x46 0x06 0xcf 0x38 0x59 0x45 0xb2 0xbe 0xc4 0xea.  This value is
        then base64-encoded (see Section 4 of [RFC4648]), to give the value
        "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=".  This value would then be echoed in
        the |Sec-WebSocket-Accept| header field.
    */
    func testExchangeKey() throws {
        let requestKey = "dGhlIHNhbXBsZSBub25jZQ=="
        let acceptKey = try WebSocket.exchange(requestKey: requestKey)
        XCTAssert(acceptKey == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }
}

class WebSocketConnectTests : XCTestCase {

    static var allTests: [(String, (WebSocketConnectTests) -> () throws -> Void)] {
        return [
            ("testBackgroundConnect", testBackgroundConnect)
        ]
    }
 
   func testBackgroundConnect() throws {
      
	let headers: [HeaderKey: String] = ["Authorized": "Bearer exampleBearer"]
	do {
        let socket = try TCPInternetSocket(scheme: "ws", hostname: "127.0.0.1", port: 80)
        try WebSocket.background(to:"ws:127.0.0.1", using: socket, maxPayloadSize: 100_000, headers: headers) { (websocket: WebSocket) throws -> Void in
                    XCTAssert(false, "No server, so this should fail to connect")
		    }
	} catch {
	    XCTAssert(true, "Expected to throw an error when there is no server available")
	}
    }
}

final class TestStream: DuplexStream {
    
    var peerAddress: String = "1.2.3.4:5678"

    var isClosed: Bool
    var buffer: Bytes

    func setTimeout(_ timeout: Double) throws {

    }

    init() {
        isClosed = false
        buffer = []
    }

    func close() throws {
        if !isClosed {
            isClosed = true
        }
    }

    func write(max: Int, from bytes: Bytes) throws -> Int {
        isClosed = false
        buffer += bytes
        return bytes.count
    }

    func flush() throws {

    }

    func read(max: Int, into buffer: inout Bytes) throws -> Int {
        if self.buffer.count == 0 {
            try close()
            return 0
        }

        if max >= self.buffer.count {
            try close()
            let data = self.buffer
            self.buffer = []
            buffer = data
            return data.count
        }

        let data = self.buffer[0..<max].array
        self.buffer.removeFirst(max)
        
        buffer = data
        return data.count
    }
}
