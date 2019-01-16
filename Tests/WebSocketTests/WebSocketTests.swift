import WebSocket
import XCTest

class WebSocketTests: XCTestCase {
    func testClient() throws {
        // ws://echo.websocket.org
        let worker = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let ws = try HTTPClient.webSocket(hostname: "echo.websocket.org", on: worker).wait()

        let promise = worker.eventLoop.newPromise(String.self)
        ws.onText { ws, text in
            promise.succeed(result: text)
            ws.close(code: .normalClosure)
        }
        ws.onCloseCode { code in
            print("code: \(code)")
        }
        let message = "Hello, world!"
        ws.send(message)
        try XCTAssertEqual(promise.futureResult.wait(), message)
        try ws.onClose.wait()
    }

    func testClientTLS() throws {
        // ws://echo.websocket.org
        let worker = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let webSocket = try HTTPClient.webSocket(scheme: .wss, hostname: "echo.websocket.org", on: worker).wait()

        let promise = worker.eventLoop.newPromise(String.self)
        webSocket.onText { ws, text in
            promise.succeed(result: text)
        }
        let message = "Hello, world!"
        webSocket.send(message)
        try XCTAssertEqual(promise.futureResult.wait(), message)
    }

    func testServer() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 8)

        let ws = HTTPServer.webSocketUpgrader(shouldUpgrade: { req in
            if req.url.path == "/deny" {
                return nil
            }
            return [:]
        }, onUpgrade: { ws, req in
            ws.send(req.url.path)
            ws.onText { ws, string in
                ws.send(string.reversed())
                if string == "close" {
                    ws.close()
                }
            }
            ws.onBinary { ws, data in
                print("data: \(data)")
            }
            ws.onCloseCode { code in
                print("code: \(code)")
            }
            ws.onClose.always {
                print("closed")
            }
        })

        let server = try HTTPServer.start(
            hostname: "127.0.0.1",
            port: 8888,
            responder: HelloResponder(),
            upgraders: [ws],
            on: group
        ) { error in
            XCTFail("\(error)")
        }.wait()

        print(server)
        // uncomment to test websocket server
        // try server.onClose.wait()
    }
    
    
    func testServerContinuation() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    
        let ws = HTTPServer.webSocketUpgrader(shouldUpgrade: { req in
            return [:]
        }, onUpgrade: { ws, req in
            ws.send(req.url.path)
            ws.onText { ws, string in
                ws.send(string.reversed())
            }
        })
        
        let server = try HTTPServer.start(
            hostname: "127.0.0.1",
            port: 8889,
            responder: HelloResponder(),
            upgraders: [ws],
            on: group
        ) { error in
            XCTFail("\(error)")
        }.wait()
        
        let client = try HTTPClient.webSocket(hostname: "127.0.0.1", port: 8889, on: group).wait()
        
        client.onText { ws, text in
            XCTAssertEqual(text, "!dlrow ,olleH")
            _ = server.close()
        }
        client.send(raw: "Hello, ", opcode: .text, fin: false)
        client.send(raw: "world", opcode: .continuation, fin: false)
        client.send(raw: "!", opcode: .continuation)
        try server.onClose.wait()
    }

    static let allTests = [
        ("testClient", testClient),
        ("testClientTLS", testClientTLS),
        ("testServer", testServer),
        ("testServerContinuation", testServerContinuation),
    ]
}

struct HelloResponder: HTTPServerResponder {
    func respond(to request: HTTPRequest, on worker: Worker) -> EventLoopFuture<HTTPResponse> {
        let res = HTTPResponse(status: .ok, body: "This is a WebSocket server")
        return worker.eventLoop.newSucceededFuture(result: res)
    }
}
