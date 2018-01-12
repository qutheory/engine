import Async
import Foundation
import COperatingSystem
import Bits

final class FrameParser: ByteParserStream {
    enum PartialFrame {
        case header([UInt8])
        case body(header: Frame.Header, totalFilled: Int)
    }
    
    /// See InputStream.Input
    public typealias Input = ByteBuffer
    
    /// See OutputStream.Output
    public typealias Output = Frame
    
    typealias Partial = PartialFrame
    
    var bufferBuilder: MutableBytesPointer
    
    var accumulated = 0
    
    var state: ByteParserStreamState<FrameParser>

    /// The maximum accepted payload size (to prevent memory attacks)
    let maximumPayloadSize: Int
    
    init(maximumPayloadSize: UInt64 = 100_000, worker: Worker) {
        assert(maximumPayloadSize < Int.max - 15, "The maximum WebSocket payload size is too large")
        assert(maximumPayloadSize > 0, "The maximum WebSocket payload size is negative or 0")
        
        self.maximumPayloadSize = numericCast(maximumPayloadSize)
        self.state = .init(worker: worker)
        
        // 2 for the header, 9 for the length, 4 for the mask
        self.bufferBuilder = MutableBytesPointer.allocate(capacity: 15 + self.maximumPayloadSize)
    }
    
    func startParsing(from buffer: ByteBuffer) throws -> ByteParserResult<PartialFrame, Frame> {
        let pointer = buffer.baseAddress!
        
        guard let header = try FrameParser.parseFrameHeader(from: pointer, length: buffer.count) else {
            // Not enough data for a header
            memcpy(bufferBuilder.advanced(by: accumulated), pointer, buffer.count)
            accumulated = accumulated &+ buffer.count
            
            return .uncompleted(.header(Array(buffer)))
        }
        
        guard header.size < numericCast(maximumPayloadSize) else {
            throw WebSocketError(.invalidBufferSize)
        }
        
        // This casting is safe because `maximumPayloadSize < Int.max - 15`
        if buffer.count &- header.consumed >= numericCast(header.size) {
            let consumed = header.consumed &+ numericCast(header.size)
            memcpy(bufferBuilder, pointer, consumed)
            
            return .completed(consuming: consumed, result: makeFrame(header: header))
        } else {
            memcpy(bufferBuilder, pointer, buffer.count)
            return .uncompleted(.body(header: header, totalFilled: buffer.count))
        }
    }
    
    private func makeFrame(header: Frame.Header) -> Frame {
        let buffer = ByteBuffer(start: bufferBuilder.advanced(by: header.consumed), count: numericCast(header.size))
        
        return Frame(op: header.op, payload: buffer, mask: header.mask, isMasked: true, isFinal: header.final)
    }
    
    func continueParsing(_ partial: PartialFrame, from buffer: ByteBuffer) throws -> ByteParserResult<PartialFrame, Frame> {
        switch partial {
        case .header(var headerBytes):
            let previouslyConsumed = headerBytes.count
            let maxNeeded = 15 - previouslyConsumed
            let pointer = buffer.baseAddress!
            let header: Frame.Header
            
            defer {
                // Always write these. Ensures that successful and uncompleted parsing are covered, always
                memcpy(bufferBuilder, headerBytes, headerBytes.count)
            }
            
            // Append until the maximum necessary
            if buffer.count >= maxNeeded {
                headerBytes += buffer[0..<maxNeeded]
                
                // This *must* succeed, there are always enough bytes for a header now
                guard let _header = try FrameParser.parseFrameHeader(from: headerBytes, length: headerBytes.count) else {
                    throw WebSocketError(.invalidFrame)
                }
                
                header = _header
            } else {
                headerBytes += buffer
                
                guard let _header = try FrameParser.parseFrameHeader(from: headerBytes, length: headerBytes.count) else {
                    return .uncompleted(.header(headerBytes))
                }
                
                header = _header
            }
            
            let offset = header.consumed - previouslyConsumed
            
            if buffer.count &- offset >= numericCast(header.size) {
                memcpy(bufferBuilder.advanced(by: header.consumed), pointer, numericCast(header.size))
                return .completed(consuming: offset &+ numericCast(header.size), result: makeFrame(header: header))
            } else {
                return .uncompleted(
                    .body(header: header, totalFilled: previouslyConsumed &+ buffer.count)
                )
            }
        case .body(let header, let filled):
            fatalError()
        }
    }
    
    static func parseFrameHeader(from base: UnsafePointer<UInt8>, length: Int) throws -> Frame.Header? {
        guard
            length > 3,
            let code = Frame.OpCode(rawValue: base[0] & 0b00001111)
        else {
            throw WebSocketError(.invalidFrame)
        }
        
        // If the FIN bit is set
        let final = base[0] & 0b10000000 == 0b10000000
        
        // Extract the payload bits
        var payloadLength = UInt64(base[1] & 0b01111111)
        let isMasked = base[1] & 0b10000000 == 0b10000000
        var consumed = 2
        var base = base.advanced(by: 2)
        
        // Binary and continuation frames don't need to be final
        if !final {
            guard code == .continuation || code == .binary || code == .close else {
                throw WebSocketError(.invalidFrameParameters)
            }
        }
        
        // Ping and pong cannot have a bigger payload than tihs
        if code == .ping || code == .pong {
            guard payloadLength < 126 else {
                throw WebSocketError(.invalidFrame)
            }
        }
        
        // Parse the payload length as UInt16 following the 126
        if payloadLength == 126 {
            guard length >= 5 else {
                return nil
            }
            
            payloadLength = base.withMemoryRebound(to: UInt16.self, capacity: 1, { UInt64($0.pointee) })
            
            base = base.advanced(by: 2)
            consumed = consumed &+ 2
            
        // payload length byte == 127 means it's followed by a UInt64
        } else if payloadLength == 127 {
            guard length >= 11 else {
                return nil
            }
            
            payloadLength = base.withMemoryRebound(to: UInt64.self, capacity: 1, { $0.pointee })
            
            base = base.advanced(by: 8)
            consumed = consumed &+ 8
        }
        
        let mask: [UInt8]?
        
        if isMasked {
            // Ensure the minimum length is available
            guard length &- consumed >= payloadLength &+ 4, payloadLength < Int.max else {
                // throw an invalidFrame for incomplete/invalid
                return nil
            }
            
            guard consumed &+ 4 < length else {
                // throw an invalidFrame for a missing mask buffer
                throw WebSocketError(.invalidMask)
            }
            
            mask = [base[0], base[1], base[2], base[3]]
            base = base.advanced(by: 4)
            consumed = consumed &+ 4
        } else {
            // throw an invalidFrame for incomplete/invalid
            guard length &- consumed >= payloadLength, payloadLength < Int.max else {
                return nil
            }
            
            mask = nil
        }
        
        return (final, code, payloadLength, mask, consumed)
    }

    deinit {
        bufferBuilder.deallocate(capacity: 15 + maximumPayloadSize)
    }
}

/// Various states the parser stream can be in
enum ProtocolParserState {
    /// normal state
    case ready
    
    /// waiting for data from upstream
    case awaitingUpstream
}
