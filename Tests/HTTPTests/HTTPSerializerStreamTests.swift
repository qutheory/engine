import Async
import Bits
import HTTP
import Foundation
import XCTest

class HTTPSerializerStreamTests: XCTestCase {
    let loop = try! DefaultEventLoop(label: "test")
    
    func testResponse() throws {
        /// output and output request for later in test
        var output: [ByteBuffer] = []

        /// setup the mock app
        let mockApp = PushStream(HTTPResponse.self)
        mockApp.stream(
            to: HTTPResponseSerializer().stream(on: loop)
        ).drain { buffer in
            output.append(buffer)
        }.catch { err in
            XCTFail("\(err)")
        }.finally {
            // closed
        }

        /// sanity check
        XCTAssertEqual(output.count, 0)

        /// emit response
        let body = "<vapor>"
        let response = try HTTPResponse(
            status: .ok,
            body: body
        )
        XCTAssertEqual(output.count, 0)
        mockApp.push(response)

        /// there should only be one buffer since we
        /// called `.drain(1)`. this buffer should contain
        /// the entire response
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output.first?.count, 45)
    }

    func testResponseStreamingBody() throws {
        /// output and output request for later in test
        var output: [Data] = []
        var closed = false

        /// setup the mock app
        let mockApp = PushStream(HTTPResponse.self)
        mockApp.stream(
            to: HTTPResponseSerializer().stream(on: loop)
        ).drain { buffer in
            output.append(Data(buffer))
        }.catch { err in
            XCTFail("\(err)")
        }.finally {
            closed = true
        }

        /// sanity check
        XCTAssertEqual(output.count, 0)

        /// create a streaming body
        let bodyEmitter = PushStream(ByteBuffer.self)

        /// emit response
        let response = HTTPResponse(
            status: .ok,
            body: HTTPBody(chunked: bodyEmitter)
        )
        mockApp.push(response)

        /// there should only be one buffer since we
        /// called `.drain(1)`. this buffer should contain
        /// the entire response sans body
        if output.count == 1 {
            let message = String(bytes: output[0], encoding: .utf8)
            XCTAssertEqual(message, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
        } else {
            XCTFail("Invalid output count: \(output.count) != 1")
        }
        /// the count should still be one, we are
        /// waiting on the body now
        XCTAssertEqual(output.count, 1)

        /// Request and emit additional output
        let a = "hello".data(using: .utf8)!
        a.withByteBuffer(bodyEmitter.push)
        if output.count == 2 {
            let message = String(data: output[1], encoding: .utf8)
            XCTAssertEqual(message, "5\r\nhello\r\n")
        } else {
            XCTFail("Invalid output count: \(output.count) != 2")
        }

        /// Request and emit additional output
        let b = "test".data(using: .utf8)!
        b.withByteBuffer(bodyEmitter.push)
        if output.count == 3 {
            let message = String(data: output[2], encoding: .utf8)
            XCTAssertEqual(message, "4\r\ntest\r\n")
        } else {
            XCTFail("Invalid output count: \(output.count) != 3")
        }

        XCTAssertEqual(output.count, 3)
        bodyEmitter.close()
        if output.count == 4 {
            let message = String(data: output[3], encoding: .utf8)
            XCTAssertEqual(message, "0\r\n\r\n")
        } else {
            XCTFail("Invalid output count: \(output.count) != 4")
        }
        /// parsing stream should remain open, just ready for another message
        XCTAssertTrue(!closed)

        /// emit response 2
        let response2 = try HTTPResponse(
            status: .ok,
            body: "hello"
        )
        mockApp.push(response2)
        if output.count == 5 {
            let message = String(data: output[4], encoding: .utf8)
            XCTAssertEqual(message, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello")
        } else {
            XCTFail("Invalid output count: \(output.count) != 5")
        }
    }

    static let allTests = [
        ("testResponse", testResponse),
        ("testResponseStreamingBody", testResponseStreamingBody),
    ]
}
