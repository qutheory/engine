#if os(Linux)

import XCTest
@testable import HTTPTests
@testable import TCPTests
@testable import RoutingTests
@testable import MultipartTests
@testable import FormURLEncodedTests
@testable import WebSocketTests
@testable import TLSTests
XCTMain([
	// MARK: HTTP
    testCase(HTTPClientTests.allTests),
    testCase(HTTPServerTests.allTests),
    testCase(HTTPSerializerTests.allTests),
    testCase(HTTPSerializerStreamTests.allTests),
    testCase(UtilityTests.allTests),

    testCase(FormURLEncodedCodableTests.allTests),
    testCase(FormURLEncodedParserTests.allTests),
    testCase(FormURLEncodedSerializerTests.allTests),

    // MARK: TCP
    testCase(MultipartTests.allTests),
    testCase(RouterTests.allTests),
    testCase(SocketsTests.allTests),
    testCase(SSLTests.allTests),
    testCase(SubProtocolMatcherTests.allTests),

    testCase(WebSocketTests.allTests),)
    testCase(SubProtocolMatcherTests.allTests),)
])

#endif
