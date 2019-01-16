/// Private `ChannelOutboundHandler` that serializes `HTTPRequest` to `HTTPClientRequestPart`.
internal final class HTTPClientRequestEncoder: ChannelOutboundHandler {
    typealias OutboundIn = HTTPRequest
    typealias OutboundOut = HTTPClientRequestPart

    let hostname: String
    
    /// Creates a new `HTTPClientRequestSerializer`.
    init(hostname: String) {
        self.hostname = hostname
    }
    
    /// See `ChannelOutboundHandler`.
    func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let req = unwrapOutboundIn(data)
        var headers = req.headers
        headers.add(name: .host, value: hostname)
        headers.replaceOrAdd(name: .userAgent, value: "Vapor/4.0 (Swift)")
        var httpHead = HTTPRequestHead(
            version: req.version,
            method: req.method,
            uri: req.url.absoluteString
        )
        httpHead.headers = headers
        ctx.write(wrapOutboundOut(.head(httpHead)), promise: nil)
        if let data = req.body.data {
            var buffer = ByteBufferAllocator().buffer(capacity: data.count)
            buffer.write(bytes: data)
            ctx.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        ctx.write(self.wrapOutboundOut(.end(nil)), promise: promise)
    }
}
