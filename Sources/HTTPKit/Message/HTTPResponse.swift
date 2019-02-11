import NIO
import NIOHTTP1

/// An HTTP response from a server back to the client.
///
///     let httpRes = HTTPResponse(status: .ok)
///
/// See `HTTPClient` and `HTTPServer`.
public struct HTTPResponse: HTTPMessage {
    /// The HTTP version that corresponds to this response.
    public var version: HTTPVersion

    /// The HTTP response status.
    public var status: HTTPResponseStatus

    /// The header fields for this HTTP response.
    /// The `"Content-Length"` and `"Transfer-Encoding"` headers will be set automatically
    /// when the `body` property is mutated.
    public var headers: HTTPHeaders

    /// The `HTTPBody`. Updating this property will also update the associated transport headers.
    ///
    ///     httpRes.body = HTTPBody(string: "Hello, world!")
    ///
    /// Also be sure to set this message's `contentType` property to a `MediaType` that correctly
    /// represents the `HTTPBody`.
    public var body: HTTPBody {
        didSet { self.headers.updateTransportHeaders(for: self.body) }
    }
    
    public var upgrader: HTTPServerProtocolUpgrader?

    /// Get and set `HTTPCookies` for this `HTTPResponse`
    /// This accesses the `"Set-Cookie"` header.
    public var cookies: HTTPCookies {
        get { return HTTPCookies.parse(setCookieHeaders: self.headers[.setCookie]) ?? [:] }
        set { newValue.serialize(into: &self) }
    }

    /// See `CustomStringConvertible`
    public var description: String {
        var desc: [String] = []
        desc.append("HTTP/\(self.version.major).\(self.version.minor) \(self.status.code) \(self.status.reasonPhrase)")
        desc.append(self.headers.debugDescription)
        desc.append(self.body.description)
        return desc.joined(separator: "\n")
    }

    // MARK: Init

    /// Creates a new `HTTPResponse`.
    ///
    ///     let httpRes = HTTPResponse(status: .ok)
    ///
    /// - parameters:
    ///     - status: `HTTPResponseStatus` to use. This defaults to `HTTPResponseStatus.ok`
    ///     - version: `HTTPVersion` of this response, should usually be (and defaults to) 1.1.
    ///     - headers: `HTTPHeaders` to include with this response.
    ///                Defaults to empty headers.
    ///                The `"Content-Length"` and `"Transfer-Encoding"` headers will be set automatically.
    ///     - body: `HTTPBody` for this response, defaults to an empty body.
    ///             See `LosslessHTTPBodyRepresentable` for more information.
    public init(
        status: HTTPResponseStatus = .ok,
        version: HTTPVersion = .init(major: 1, minor: 1),
        headers: HTTPHeaders = .init(),
        body: LosslessHTTPBodyRepresentable = HTTPBody()
    ) {
        self.init(
            status: status,
            version: version,
            headersNoUpdate: headers,
            body: body.convertToHTTPBody()
        )
        self.headers.updateTransportHeaders(for: self.body)
    }


    /// Internal init that creates a new `HTTPResponse` without sanitizing headers.
    public init(
        status: HTTPResponseStatus,
        version: HTTPVersion,
        headersNoUpdate headers: HTTPHeaders,
        body: HTTPBody
    ) {
        self.status = status
        self.version = version
        self.headers = headers
        self.body = body
    }
}
