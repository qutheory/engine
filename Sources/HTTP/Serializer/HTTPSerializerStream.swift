import Async
import Bits
import Foundation
import TCP

/// Stream wrapper around an HTTP serializer.
public final class HTTPSerializerStream<Serializer>: Async.Stream, ConnectionContext
    where Serializer: HTTPSerializer
{
    /// See InputStream.Input
    public typealias Input = Serializer.Message
    
    /// See OutputStream.Output
    public typealias Output = ByteBuffer
    
    /// The underlying serializer
    private let serializer: Serializer
    
    /// Use this to request more messages from upstream.
    private var upstream: ConnectionContext?
    
    /// Amount of requested output remaining
    private var remainingByteBuffersRequested: UInt
    
    /// The serializer's state
    private var state: HTTPSerializerStreamState<Serializer.Message>
    
    /// A buffer used to store writes in temporarily
    private let writeBuffer: MutableByteBuffer
    
    /// Downstream byte buffer input stream
    private var downstream: AnyInputStream<Output>?
    
    /// Creates a new serializer stream. Use `HTTPSerializer.stream()` to call this method.
    internal init(serializer: Serializer, bufferSize: Int) {
        self.serializer = serializer
        remainingByteBuffersRequested = 0
        state = .ready
        let pointer = MutableBytesPointer.allocate(capacity: bufferSize)
        writeBuffer = MutableByteBuffer(start: pointer, count: bufferSize)
    }
    
    /// See ConnectionContext.connection
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .request(let count):
            remainingByteBuffersRequested += count
            update()
        case .cancel:
            /// FIXME: cancel
            break
        }
    }
    
    /// See InputStream.input
    public func input(_ event: InputEvent<Serializer.Message>) {
        switch event {
        case .close:
            downstream?.close()
        case .connect(let upstream):
            remainingByteBuffersRequested = 0
            self.upstream = upstream
        case .error(let error):
            downstream?.error(error)
        case .next(let input):
            state = .messageReady(input)
            update()
        }
    }
    
    /// See OutputStream.onOutput
    public func output<I>(to inputStream: I) where I: Async.InputStream, Output == I.Input {
        downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }
    
    
    /// Update based on state.
    private func update() {
        guard remainingByteBuffersRequested > 0 else {
            return
        }
        
        switch state {
        case .ready:
            // we are ready for a message, request it
            upstream?.request()
            state = .awaitingMessage
        case .awaitingMessage: break
        case .messageReady(let message):
            serializer.setMessage(to: message)
            state = .messageStreaming(message.body)
            update()
        case .messageStreaming(let body):
            /// continue streaming the message until
            /// the serializer indicates it is done
            let serialized = try! serializer.serialize(into: writeBuffer)
            let frame = ByteBuffer(start: writeBuffer.baseAddress, count: serialized)
            
            /// the serializer indicates it is done w/ this message
            if serializer.ready {
                /// handle the body separately
                switch body.storage {
                case .none, .dispatchData, .data, .staticString, .string:
                    state = .ready
                case .chunkedOutputStream(let closure):
                    state = .chunkedStreamingBodyReady(closure)
                case .binaryOutputStream(_, let stream):
                    state = .streamingBody(stream)
                }
            }
            
            remainingByteBuffersRequested -= 1
            downstream?.next(frame)
            update()
        case .chunkedStreamingBodyReady(let closure):
            let stream = closure(HTTPChunkEncodingStream())
            
            stream.drain { req in
                self.state = .bodyStreaming(req)
            }.output { buffer in
                self.remainingByteBuffersRequested -= 1
                self.downstream?.next(buffer)
                self.update()
            }.catch { error in
                self.downstream?.error(error)
                self.close()
            }.finally {
                // TODO: Trailer headers
                self.state = .ready
                self.update()
            }
            
            stream.request()
        case .streamingBody(let stream):
            stream.drain { req in
                self.state = .bodyStreaming(req)
            }.output { buffer in
                self.remainingByteBuffersRequested -= 1
                self.downstream?.next(buffer)
                self.update()
            }.catch { error in
                self.downstream?.error(error)
                self.close()
            }.finally {
                // TODO: Trailer headers
                self.state = .ready
                self.update()
            }
            
            self.update()
        case .bodyStreaming(let req):
            req.request()
        }
    }
    
    deinit {
        writeBuffer.baseAddress!.deinitialize(count: writeBuffer.count)
        writeBuffer.baseAddress!.deallocate(capacity: writeBuffer.count)
    }
}

enum HTTPSerializerStreamState<Message> {
    case ready
    case awaitingMessage
    case messageReady(Message)
    case messageStreaming(HTTPBody)
    case chunkedStreamingBodyReady(HTTPBody.OutputChunkedStreamClosure)
    case streamingBody(AnyOutputStream<ByteBuffer>)
    case bodyStreaming(ConnectionContext)
}

extension HTTPSerializer {
    /// Create a stream for this serializer.
    public func stream(bufferSize: Int = .maxTCPPacketSize) -> HTTPSerializerStream<Self> {
        return HTTPSerializerStream(serializer: self, bufferSize: bufferSize)
    }
}

