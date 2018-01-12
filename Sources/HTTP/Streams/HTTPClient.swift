import Async
import Bits

/// An HTTP client wrapped around TCP client
///
/// Can handle a single `Request` at a given time.
///
/// Multiple requests at the same time are subject to unknown behaviour
///
/// [Learn More →](https://docs.vapor.codes/3.0/http/client/)
public final class HTTPClient<SourceStream, SinkStream> where
    SourceStream: OutputStream,
    SourceStream.Output == ByteBuffer,
    SinkStream: InputStream,
    SinkStream.Input == ByteBuffer
{
    /// Inverse stream, takes in responses and outputs requests
    private let clientStream: HTTPClientStream<SourceStream, SinkStream>

    /// Creates a new Client wrapped around a `TCP.Client`
    public init(source: SourceStream, sink: SinkStream, worker: Worker, maxResponseSize: Int = 10_000_000) {
        self.clientStream = HTTPClientStream<SourceStream, SinkStream>(
            source: source,
            sink: sink,
            worker: worker,
            maxResponseSize: maxResponseSize
        )
    }

    /// Sends an HTTP request.
    public func send(_ request: HTTPRequest) -> Future<HTTPResponse> {
        let promise = Promise(HTTPResponse.self)
        clientStream.requestQueue.insert(request, at: 0)
        clientStream.responseQueue.insert(promise, at: 0)
        clientStream.request()
        clientStream.update()
        return promise.future
    }
}
