import Foundation
import XCTest

import Core
import Transport

class StreamBufferTests: XCTestCase {
    static let allTests = [
        ("testStreamBufferSending", testStreamBufferSending),
        ("testStreamBufferSendingImmediateFlush", testStreamBufferSendingImmediateFlush),
        ("testStreamBufferReceiving", testStreamBufferReceiving),
        ("testStreamBufferSkipEmpty", testStreamBufferSkipEmpty),
        ("testStreamBufferFlushes", testStreamBufferFlushes),
        ("testStreamBufferMisc", testStreamBufferMisc)
    ]

    lazy var testStream: TestStream! = TestStream()
    lazy var streamBuffer: StreamBuffer! = StreamBuffer(self.testStream)

    override func tearDown() {
        super.tearDown()
        // reset
        testStream = nil
        streamBuffer = nil
    }

    func testStreamBufferSending() throws {
        try streamBuffer.send([1,2,3,4,5])
        XCTAssert(testStream.buffer == [], "underlying shouldn't have sent bytes yet")
        try streamBuffer.flush()
        XCTAssert(testStream.buffer == [1,2,3,4,5], "buffer should have sent bytes")
    }

    func testStreamBufferSendingImmediateFlush() throws {
        try streamBuffer.send([1,2,3,4,5], flushing: true)
        XCTAssert(testStream.buffer == [1,2,3,4,5], "buffer should have sent bytes")
    }

    func testStreamBufferReceiving() throws {
        // loads test stream
        try testStream.send([1,2,3,4,5])

        let first = try streamBuffer.receive()
        XCTAssert(first == 1)
        XCTAssert(testStream.buffer == [], "test stream should be entirely received by buffer")

        let remaining = try streamBuffer.receive(max: 200)
        XCTAssert(remaining == [2,3,4,5])
    }

    func testStreamBufferSkipEmpty() throws {
        try streamBuffer.send([], flushing: true)
        XCTAssert(testStream.flushedCount == 0, "should not attempt to flush empty buffer")
    }

    func testStreamBufferFlushes() throws {
        do {
            try streamBuffer.send(1)
            try streamBuffer.flush()
            XCTAssert(testStream.flushedCount == 1, "should have flushed")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testStreamBufferMisc() throws {
        do {
            try streamBuffer.close()
            XCTAssert(testStream.closed, "stream buffer should close underlying stream")
            XCTAssert(streamBuffer.closed, "stream buffer should reflect closed status of underlying stream")

            try streamBuffer.setTimeout(42)
            XCTAssert(testStream.timeout == 42, "stream buffer should set underlying timeout")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}


final class TestStream: Transport.Stream {

    var peerAddress: String = "1.2.3.4:5678"

    var closed: Bool
    var buffer: Bytes
    var timeout: Double = -1
    // number of times flush was called
    var flushedCount = 0

    func setTimeout(_ timeout: Double) throws {
        self.timeout = timeout
    }

    init() {
        closed = false
        buffer = []
    }

    func close() throws {
        if !closed {
            closed = true
        }
    }

    func send(_ bytes: Bytes) throws {
        closed = false
        buffer += bytes
    }

    func flush() throws {
        flushedCount += 1
    }

    func receive(max: Int) throws -> Bytes {
        if buffer.count == 0 {
            try close()
            return []
        }

        if max >= buffer.count {
            try close()
            let data = buffer
            buffer = []
            return data
        }

        let data = buffer[0..<max]
        buffer.removeFirst(max)
        
        return Bytes(data)
    }
}
