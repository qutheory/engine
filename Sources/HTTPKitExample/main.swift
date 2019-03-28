import HTTPKit
import Logging

let hostname = "127.0.0.1"
let elg = MultiThreadedEventLoopGroup(numberOfThreads: 8)

let client = HTTPClient(on: elg)

let res0 = client.send(HTTPRequest(method: .GET, url: "http://httpbin.org/status/200"))
let res1 = client.send(HTTPRequest(method: .GET, url: "http://httpbin.org/status/201"))
let res2 = client.send(HTTPRequest(method: .GET, url: "http://httpbin.org/status/2020"))

try print(res0.wait().status)
try print(res1.wait().status)
try print(res2.wait().status)

let res = HTTPResponse(body: HTTPBody(staticString: "pong"))

struct EchoResponder: HTTPServerDelegate {
    func respond(to req: HTTPRequest, on channel: Channel) -> EventLoopFuture<HTTPResponse> {
        let promise = channel.eventLoop.makePromise(of: HTTPResponse.self)
        print("got: \(req)")
        if let stream = req.body.stream {
            stream.read { chunk, stream in
                switch chunk {
                case .chunk(var chunk):
                    let string = chunk.readString(length: chunk.readableBytes) ?? ""
                    print("streamed: \(string.debugDescription)")
                case .end:
                    promise.succeed(res)
                case .error(let error):
                    promise.fail(error)
                }
            }
        } else {
            promise.succeed(res)
        }
        return promise.futureResult
    }
}
let responder = EchoResponder()

print("Plaintext server starting on http://\(hostname):8080")

let plaintextServer = HTTPServer(
    config: .init(
        hostname: hostname,
        port: 8080,
        supportVersions: [.one]
    ),
    on: elg
)
try plaintextServer.start(delegate: responder).wait()


// Uncomment to start only plaintext server
// plaintextServer.onClose.wait()

print("TLS server starting on https://\(hostname):8443")

let tlsServer = HTTPServer(
    config: .init(
        hostname: hostname,
        port: 8443,
        supportVersions: [.one, .two],
        tlsConfig: .forServer(
            certificateChain: [.file("/Users/tanner0101/dev/vapor/http-kit/certs/cert.pem")],
            privateKey: .file("/Users/tanner0101/dev/vapor/http-kit/certs/key.pem")
        )
    ),
    on: elg
)
try tlsServer.start(delegate: responder).wait()

_ = try plaintextServer.onClose
    .and(tlsServer.onClose).wait()

try elg.syncShutdownGracefully()
