import Async
import Bits
import Dispatch
import Foundation

/// A helper for Request and Response serializer that keeps state
internal enum HTTPSerializerState {
    case noMessage
    case firstLine
    case headers
    case crlf
    case staticBody
    
    mutating func next() {
        switch self {
        case .firstLine: self = .headers
        case .headers: self = .crlf
        case .crlf: self = .staticBody
        default: self = .noMessage
        }
    }
}

/// Internal Swift HTTP serializer protocol.
public protocol HTTPSerializer: class {
    /// The message the parser handles.
    associatedtype Message: HTTPMessage
    
    /// Indicates that the message headers have been flushed (and this serializer is ready)
    var ready: Bool { get }

    /// Sets the message being serialized.
    /// Becomes `nil` after completely serialized.
    /// Setting this property resets the serializer.
    func setMessage(to message: Message)

    /// Serializes data from the supplied message into the buffer.
    /// Returns the number of bytes serialized.
    func serialize(into buffer: MutableByteBuffer) throws -> Int
}

internal protocol _HTTPSerializer: HTTPSerializer {
    /// Serialized message
    var firstLine: [UInt8]? { get set }
    
    /// Headers
    var headersData: Data? { get set }

    /// Body data
    var staticBodyData: HTTPBody? { get set }
    
    /// The current offset of the currently serializing entity
    var offset: Int { get set }
    
    /// Keeps track of the state of serialization
    var state: HTTPSerializerState { get set }
}

extension _HTTPSerializer {
    /// Indicates that the message headers have been flushed (and this serializer is ready)
    public var ready: Bool {
        return self.state == .noMessage
    }
    
    /// See HTTPSerializer.serialize
    public func serialize(into buffer: MutableByteBuffer) throws -> Int {
        var bufferSize: Int
        var writeOffset = 0
        
        repeat {
            let writeSize: Int
            let outputSize = buffer.count - writeOffset
            
            switch state {
            case .noMessage:
                throw HTTPError(identifier: "no-response", reason: "Serialization requested without a response")
            case .firstLine:
                guard let firstLine = self.firstLine else {
                    throw HTTPError(identifier: "invalid-state", reason: "Missing first line metadata")
                }
                
                bufferSize = firstLine.count
                writeSize = min(outputSize, bufferSize - offset)
                
                firstLine.withUnsafeBytes { pointer in
                    _ = memcpy(buffer.baseAddress!.advanced(by: writeOffset), pointer.baseAddress!.advanced(by: offset), writeSize)
                }
            case .headers:
                guard let headersData = self.headersData else {
                    throw HTTPError(identifier: "invalid-state", reason: "Missing header state")
                }
                
                bufferSize = headersData.count
                writeSize = min(outputSize, bufferSize - offset)
                
                headersData.withByteBuffer { headerBuffer in
                    _ = memcpy(buffer.baseAddress!.advanced(by: writeOffset), headerBuffer.baseAddress!.advanced(by: offset), writeSize)
                }
            case .crlf:
                bufferSize = 2
                writeSize = min(outputSize, bufferSize - offset)
                
                crlf.withUnsafeBufferPointer { crlfBuffer in
                    _ = memcpy(buffer.baseAddress!.advanced(by: writeOffset), crlfBuffer.baseAddress!.advanced(by: offset), writeSize)
                }
            case .staticBody:
                if let bodyData = self.staticBodyData {
                    bufferSize = bodyData.count
                    writeSize = min(outputSize, bufferSize - offset)
                    try bodyData.withUnsafeBytes { pointer in
                        _ = memcpy(buffer.baseAddress!.advanced(by: writeOffset), pointer.advanced(by: offset), writeSize)
                    }
                } else {
                    state.next()
                    continue
                }
            }
            
            writeOffset += writeSize
            
            if offset + writeSize < bufferSize {
                offset += writeSize
                return writeOffset
            } else {
                offset = 0
                state.next()
            }
        } while !self.ready
        
        return writeOffset
    }
}

fileprivate let crlf: [UInt8] = [.carriageReturn, .newLine]

