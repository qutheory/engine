# Engine

Engine is a collection of low level transport protocols implemented in pure Swift intended for use in server side and client side applications. It is used as the core transport layer in [Vapor](https://github.com/qutheory/github).

##### [Engine](#httpclient)
HTTP and Stream layers

##### [WebSockets](#websockets)
Realtime websockets

##### [SMTP](#smtp)
Send emails.

## 🌎 Current Environment

| Engine | Xcode | Swift |
|:-:|:-:|:-:|
|0.1.x|8.0 Beta|DEVELOPMENT-SNAPSHOT-2016-06-20-a|

## ⛔️ Important Install Notes

[StackOverflow](http://stackoverflow.com/questions/38296145/vapor-web-framework-error-swift-does-not-support-the-sdk-macosx10-11-sdk)

Vapor requires Xcode 8 to be fully installed including command line tools. Once Xcode 8 is opened, select:

```
Xcode > Preferences > Location > Command Line Tools > Xcode 8
```

[More Help Here!](http://stackoverflow.com/questions/38296145/vapor-web-framework-error-swift-does-not-support-the-sdk-macosx10-11-sdk) Or [visit us in slack](http://slack.qutheory.io).

## Linux Ready

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)

## Quick Start

#### HTTPClient

```Swift
import Engine

let response = try HTTPClient<TCPClientStream>.get("http://pokeapi.co/api/v2/pokemon/")
print(response)
```

#### HTTPServer

```Swift
import Engine

final class Responder: HTTPResponder {
    func respond(to request: Request) throws -> Response {
        let body = "Hello World".makeBody()
        return Response(body: body)
    }
}

let server = try HTTPServer<TCPServerStream, HTTPParser<HTTPRequest>, HTTPSerializer<HTTPResponse>>(port: port)

print("visit http://localhost:\(port)/")
try server.start(responder: Responder()) { error in
    print("Got error: \(error)")
}
```

#### WebSocket Client

```Swift
import Engine
import WebSockets

try WebSocket.connect(to: url) { ws in
    print("Connected to \(url)")

    ws.onText = { ws, text in
        print("[event] - \(text)")
    }

    ws.onClose = { ws, _, _, _ in
        print("\n[CLOSED]\n")
    }
}
```

#### WebSocket Server

```Swift
import Engine
import WebSockets

final class Responder: HTTPResponder {
    func respond(to request: Request) throws -> Response {
        return try request.upgradeToWebSocket { ws in
            print("[ws connected]")

            ws.onText = { ws, text in
                print("[ws text] \(text)")
                try ws.send("🎙 \(text)")
            }

            ws.onClose = { _, code, reason, clean in
                print("[ws close] \(clean ? "clean" : "dirty") \(code?.description ?? "") \(reason ?? "")")
            }
        }
    }
}

let server = try HTTPServer<TCPServerStream, HTTPParser<HTTPRequest>, HTTPSerializer<HTTPResponse>>(port: port)

print("Connect websocket to http://localhost:\(port)/")
try server.start(responder: Responder()) { error in
    print("Got server error: \(error)")
}
```

#### SMTP

```Swift
import SMTP

let credentials = SMTPCredentials(user: "server-admin-login",
                                  pass: "secret-server-password")

let from = EmailAddress(name: "Password Rest",
                        address: "noreply@myapp.com")
let to = "some-user@random.com"
let email: Email = Email(from: from,
                         to: to,
                         subject: "Vapor SMTP - Simple",
                         body: "Hello from Vapor SMTP 👋")

let client = try SMTPClient<TCPClientStream>.makeGMailClient()
try client.send(email, using: credentials)
```

## Architecture

#### HTTPServer

The HTTPServer is responsible for listening and accepting remote connections, then relaying requests and responses between the received connection and the responder.

![](/Resources/Diagrams/HTTPServerDiagram.png)

#### HTTPClient

The HTTPClient is responsible for establishing remote connections and relaying requests and responses between the remote connection and the caller.

![](/Resources/Diagrams/HTTPClientDiagram.png)

## 📖 Documentation

Visit official Vapor [Documentation](http://docs.qutheory.io) for extensive information on getting setup, using, and deploying Vapor.

## 💙 Code of Conduct

Our goal is to create a safe and empowering environment for anyone who decides to use or contribute to Vapor. Please help us make the community a better place by abiding to this [Code of Conduct](https://github.com/qutheory/vapor/blob/master/CODE_OF_CONDUCT.md) during your interactions surrounding this project.

## 💡 Evolution

Contributing code isn't the only way to participate in Vapor. Taking a page out of the Swift team's playbook, we want _you_ to participate in the evolution of the Vapor framework. File a GitHub issue on this repository to start a discussion or suggest an awesome idea.

## 💧 Community

We pride ourselves on providing a diverse and welcoming community. Join your fellow Vapor developers in [our slack](slack.qutheory.io) and take part in the conversation.

## 🔧 Compatibility

Vapor has been tested on OS X 10.11, Ubuntu 14.04, and Ubuntu 15.10.

Our homepage [http://qutheory.io](http://qutheory.io) is currently running using Vapor on DigitalOcean.

## 👥 Authors

Made by [Tanner Nelson](https://twitter.com/tanner0101), [Logan Wright](https://twitter.com/logmaestro), and the hundreds of members of the Qutheory community.
