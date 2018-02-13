import Transport
import CHTTP
import URI

/// Parses responses from a readable stream.
public final class ResponseParser: CHTTPParser {
    // Internal variables to conform
    // to the C HTTP parser protocol.
    var parser: http_parser
    var settings: http_parser_settings
    var state:  CHTTPParserState
    
    private var parsedBytes = 0
    
    // The maximum amount of bytes to parse
    private let maximumSize: Int
    
    /// Creates a new Response parser.
    public init(maxSize: Int) {
        self.maximumSize = maxSize
        self.parser = http_parser()
        self.settings = http_parser_settings()
        self.state = .ready
        http_parser_init(&parser, HTTP_RESPONSE)
        initialize(&settings)
    }
    
    /// Parses a Response from the stream.
    public func parse(max: Int, from buffer: Bytes) throws -> Response? {
        guard buffer.count + parsedBytes <= maximumSize else {
            throw ParserError.invalidMessage
        }
        
        defer {
            parsedBytes += buffer.count
        }
        
        let results: ParseResults
        
        switch state {
        case .ready:
            // create a new results object and set
            // a reference to it on the parser
            let newResults = ParseResults.set(on: &parser)
            results = newResults
            state = .parsing
        case .parsing:
            // get the current parse results object
            guard let existingResults = ParseResults.get(from: &parser) else {
                return nil
            }
            results = existingResults
        }
        
        /// parse the message using the C HTTP parser.
        try executeParser(max: max, from: buffer)
        
        guard results.isComplete else {
            return nil
        }
        
        // the results have completed, so we are ready
        // for a new request to come in
        state = .ready
        ParseResults.remove(from: &parser)
        
        
        let status = Status(statusCode: Int(parser.status_code))
        
        guard let version = results.version else {
            throw ParserError.invalidMessage
        }
        
        let response = Response(
            version: version,
            status: status,
            headers: results.headers,
            body: .data(results.body)
        )
        
        self.parsedBytes = 0
        
        return response
    }
}

extension ResponseParser {
    @available(*, deprecated, message: "Use init(maxSize:) instead.")
    public convenience init() {
        self.init(maxSize: Int.max)
    }
}
