import Foundation
import NIO
import NIOHTTP1

/// An HTTP request from a client to a server.
///
///     let httpReq = HTTPRequest(method: .GET, url: "/hello")
///
/// See `HTTPClient` and `HTTPServer`.
public struct HTTPRequest: HTTPMessage {
    // MARK: Properties

    /// The HTTP method for this request.
    ///
    ///     httpReq.method = .GET
    ///
    public var method: HTTPMethod

    /// The URL used on this request.
    public var url: URL {
        get { return URL(string: self.urlString) ?? .root }
        set { self.urlString = newValue.absoluteString }
    }

    /// The unparsed URL string. This is usually set through the `url` property.
    ///
    ///     httpReq.urlString = "/welcome"
    ///
    public var urlString: String

    /// The version for this HTTP request.
    public var version: HTTPVersion

    /// The header fields for this HTTP request.
    /// The `"Content-Length"` and `"Transfer-Encoding"` headers will be set automatically
    /// when the `body` property is mutated.
    public var headers: HTTPHeaders

    /// The `HTTPBody`. Updating this property will also update the associated transport headers.
    ///
    ///     httpReq.body = HTTPBody(string: "Hello, world!")
    ///
    /// Also be sure to set this message's `contentType` property to a `MediaType` that correctly
    /// represents the `HTTPBody`.
    public var body: HTTPBody {
        didSet { self.headers.updateTransportHeaders(for: self.body) }
    }
    
    public var isKeepAlive: Bool
    
    public var upgrader: HTTPClientProtocolUpgrader?

    /// Get and set `HTTPCookies` for this `HTTPRequest`
    /// This accesses the `"Cookie"` header.
    public var cookies: HTTPCookies {
        get { return headers.firstValue(name: .cookie).flatMap(HTTPCookies.parse) ?? [:] }
        set { newValue.serialize(into: &self) }
    }

    /// See `CustomStringConvertible`
    public var description: String {
        var desc: [String] = []
        desc.append("\(self.method) \(self.url) HTTP/\(self.version.major).\(self.version.minor)")
        desc.append(self.headers.debugDescription)
        desc.append(self.body.description)
        return desc.joined(separator: "\n")
    }

    // MARK: Init

    /// Creates a new `HTTPRequest`.
    ///
    ///     let httpReq = HTTPRequest(method: .GET, url: "/hello")
    ///
    /// - parameters:
    ///     - method: `HTTPMethod` to use. This defaults to `HTTPMethod.GET`.
    ///     - url: A `URLRepresentable` item that represents the request's URL.
    ///            This defaults to `"/"`.
    ///     - version: `HTTPVersion` of this request, should usually be (and defaults to) 1.1.
    ///     - headers: `HTTPHeaders` to include with this request.
    ///                Defaults to empty headers.
    ///                The `"Content-Length"` and `"Transfer-Encoding"` headers will be set automatically.
    ///     - body: `HTTPBody` for this request, defaults to an empty body.
    ///             See `LosslessHTTPBodyRepresentable` for more information.
    public init(
        method: HTTPMethod = .GET,
        url: URLRepresentable = URL.root,
        version: HTTPVersion = .init(major: 1, minor: 1),
        headers: HTTPHeaders = .init(),
        body: HTTPBody = .empty
    ) {
        self.init(
            method: method,
            urlString: url.convertToURL()?.absoluteString ?? "/",
            version: version,
            headersNoUpdate: headers,
            body: body.convertToHTTPBody()
        )
        self.headers.updateTransportHeaders(for: self.body)
    }

    /// Internal init that creates a new `HTTPRequest` without sanitizing headers.
    public init(
        method: HTTPMethod,
        urlString: String,
        version: HTTPVersion = .init(major: 1, minor: 1),
        headersNoUpdate headers: HTTPHeaders = .init(),
        body: HTTPBody = .init()
    ) {
        self.method = method
        self.urlString = urlString
        self.version = version
        self.headers = headers
        self.body = body
        self.isKeepAlive = true
    }
}
