import Async
import Foundation
import HTTP

public final class FormURLDecoder {
    /// Internal parser
    let parser: FormURLEncodedParser

    /// If true, empty values will be omitted
    public var omitEmptyValues: Bool

    /// If true, flags will be omitted
    public var omitFlags: Bool
    
    /// The maximum amount of data to decode
    ///
    /// Used to prevent memory buffer attacks
    public var maxBodySize: Int

    /// Create a new form-urlencoded decoder.
    public init(omitEmptyValues: Bool = false, omitFlags: Bool = false) {
        self.parser = FormURLEncodedParser()
        self.omitFlags = omitFlags
        self.omitEmptyValues = omitEmptyValues
        self.maxBodySize = 100_000
    }

    /// Decodes a decodable type from form-urlencoded data
    public func decode<D>(_ type: D.Type, from body: HTTPBody) throws -> Future<D> where D: Decodable {
        return body.makeData(max: maxBodySize).map(to: D.self) { data in
            let formURLData = try self.parser.parse(data, omitEmptyValues: self.omitEmptyValues, omitFlags: self.omitFlags)
            let decoder = _FormURLDecoder(data: .dictionary(formURLData), codingPath: [])
            return try D(from: decoder)
        }
    }
}

/// Internal form urlencoded decoder.
/// See FormURLDecoder for the public decoder.
final class _FormURLDecoder: Decoder {
    /// See Decoder.codingPath
    let codingPath: [CodingKey]

    /// See Decoder.userInfo
    let userInfo: [CodingUserInfoKey: Any]

    /// The data being decoded
    let data: FormURLEncodedData

    /// Creates a new form urlencoded decoder
    init(data: FormURLEncodedData, codingPath: [CodingKey]) {
        self.data = data
        self.codingPath = codingPath
        self.userInfo = [:]
    }

    /// See Decoder.container
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key>
        where Key: CodingKey
    {
        let container = FormURLKeyedDecoder<Key>(data: data, codingPath: codingPath)
        return .init(container)
    }

    /// See Decoder.unkeyedContainer
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return FormURLUnkeyedDecoder(data: data, codingPath: codingPath)
    }

    /// See Decoder.singleValueContainer
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return FormURLSingleValueDecoder(data: data, codingPath: codingPath)
    }
}

extension DecodingError {
    public static func typeMismatch(_ type: Any.Type, atPath path: [CodingKey]) -> DecodingError {
        let pathString = path.map { $0.stringValue }.joined(separator: ".")
        let context = DecodingError.Context(
            codingPath: path,
            debugDescription: "No \(type) was found at path \(pathString)"
        )
        return Swift.DecodingError.typeMismatch(type, context)
    }
}
