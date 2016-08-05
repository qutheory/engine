import HTTP
import Transport

import Dispatch

let queue = DispatchQueue.global(qos: .background)
queue.async {
    print("I'm running in background")
}

func client() throws {
    let response = try Client<TCPClientStream>.get("http://pokeapi.co/api/v2/pokemon/")
    print(response)
}

func server() throws {
    final class Responder: HTTP.Responder {
        func respond(to request: Request) throws -> Response {
            let body = "Hello World".makeBody()
            return Response(body: body)
        }
    }

    let server = try Server<TCPServerStream, Parser<Request>, Serializer<Response>>(port: port)

    print("visit http://localhost:\(port)/")
    try server.start(responder: Responder()) { error in
        print("Got error: \(error)")
    }
}

try server()
