import NIO

extension HTTPMessage {
    /// Represents the information we have about the remote peer of this message.
    ///
    /// The peer (remote/client) address is important for availability (block bad clients by their IP) or even security.
    /// We can always get the remote IP of the connection from the `Channel`. However, when clients go through
    /// a proxy or a load balancer, we'd like to get the original client's IP. Most proxy servers and load
    /// balancers communicate the information about the original client in certain headers.
    ///
    /// See https://en.wikipedia.org/wiki/X-Forwarded-For
    public func remotePeer(on channel: Channel? = nil) -> HTTPPeer {
        return .init(self, channel: channel)
    }
}

/// Contain's information about the remote peer.
public struct HTTPPeer: CustomStringConvertible {
    /// `HTTPMessage` that peer info will be extracted from.
    let message: HTTPMessage
    
    let channel: Channel?

    /// See `CustomStringConvertible`.
    public var description: String {
        var desc = ""
        if let scheme = scheme {
            desc += "\(scheme)://"
        }
        if let hostname = hostname {
            desc += "\(hostname)"
        }
        if let port = port {
            desc += ":\(port)"
        }
        return desc
    }

    /// Creates a new `HTTPPeer` wrapper around an `HTTPMessage`.
    init(_ message: HTTPMessage, channel: Channel?) {
        self.message = message
        self.channel = channel
    }

    /// The peer's scheme, like `http` or `https`.
    public var scheme: String? {
        return self.message.headers.firstValue(name: .forwarded).flatMap(Forwarded.parse)?.proto
            ?? self.message.headers.firstValue(name: .init("X-Forwarded-Proto"))
            ?? self.message.headers.firstValue(name: .init("X-Scheme"))
    }

    /// The peer's hostname.
    public var hostname: String? {
        return self.message.headers.firstValue(name: .forwarded).flatMap(Forwarded.parse)?.for
            ?? self.message.headers.firstValue(name: .init("X-Forwarded-For"))
            ?? self.channel?.remoteAddress?.hostname
    }

    /// The peer's port.
    public var port: Int? {
        return self.message.headers.firstValue(name: .init("X-Forwarded-Port")).flatMap(Int.init)
            ?? self.channel?.remoteAddress?.port.flatMap(Int.init)
    }
}

// MARK: Private

private extension SocketAddress {
    /// Returns the hostname for this `SocketAddress` if one exists.
    var hostname: String? {
        switch self {
        case .unixDomainSocket: return nil
        case .v4(let v4): return v4.host
        case .v6(let v6): return v6.host
        }
    }
}

/// Parses the `Forwarded` header.
private struct Forwarded {
    /// "for" section of the header
    var `for`: String?

    /// "proto" section of the header.
    var proto: String?

    /// "by" section of the header.
    var by: String?

    /// Creates a new `Forwaded` header object from the header value.
    static func parse(_ data: String) -> Forwarded? {
        guard let value = HTTPHeaderValue.parse(data) else {
            return nil
        }

        return .init(for: value.parameters["for"], proto: value.parameters["proto"], by: value.parameters["by"])
    }
}
