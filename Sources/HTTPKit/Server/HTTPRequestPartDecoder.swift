import Logging

final class HTTPRequestPartDecoder: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HTTPRequest
    
    /// Tracks current HTTP server state
    enum RequestState {
        /// Waiting for request headers
        case ready
        /// Waiting for the body
        /// This allows for performance optimization incase
        /// a body never comes
        case awaitingBody(HTTPRequestHead)
        // first chunk
        case awaitingEnd(HTTPRequestHead, ByteBuffer)
        /// Collecting streaming body
        case streamingBody(HTTPBody.Stream)
    }
    
    /// Current HTTP state.
    var requestState: RequestState
    
    /// Maximum body size allowed per request.
    private let maxBodySize: Int
    
    private let logger: Logger
    
    init(maxBodySize: Int) {
        self.maxBodySize = maxBodySize
        self.requestState = .ready
        self.logger = Logger(label: "http-kit.server-decoder")
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        assert(context.channel.eventLoop.inEventLoop)
        let part = self.unwrapInboundIn(data)
        self.logger.debug("got \(part)")
        switch part {
        case .head(let head):
            switch self.requestState {
            case .ready: self.requestState = .awaitingBody(head)
            default: assertionFailure("Unexpected state: \(self.requestState)")
            }
        case .body(let chunk):
            switch self.requestState {
            case .ready: assertionFailure("Unexpected state: \(self.requestState)")
            case .awaitingBody(let head):
                self.requestState = .awaitingEnd(head, chunk)
            case .awaitingEnd(let head, let bodyStart):
                let stream = HTTPBody.Stream(on: context.channel.eventLoop)
                self.requestState = .streamingBody(stream)
                self.fireRequestRead(head: head, body: .init(stream: stream), context: context)
                stream.write(.chunk(bodyStart))
                stream.write(.chunk(chunk))
            case .streamingBody(let stream):
                stream.write(.chunk(chunk))
            }
        case .end(let tailHeaders):
            assert(tailHeaders == nil, "Tail headers are not supported.")
            switch self.requestState {
            case .ready: assertionFailure("Unexpected state: \(self.requestState)")
            case .awaitingBody(let head):
                self.fireRequestRead(head: head, body: .empty, context: context)
            case .awaitingEnd(let head, let chunk):
                self.fireRequestRead(head: head, body: .init(buffer: chunk), context: context)
            case .streamingBody(let stream): stream.write(.end)
            }
            self.requestState = .ready
        }
    }
    
    private func fireRequestRead(head: HTTPRequestHead, body: HTTPBody, context: ChannelHandlerContext) {
        var req = HTTPRequest(
            method: head.method,
            urlString: head.uri,
            version: head.version,
            headersNoUpdate: head.headers,
            body: body
        )
        #warning("TODO: https://github.com/apple/swift-nio/issues/849")
        switch head.version.major {
        case 2:
            req.isKeepAlive = true
        default:
            req.isKeepAlive = head.isKeepAlive
        }
        context.fireChannelRead(self.wrapInboundOut(req))
    }
}
