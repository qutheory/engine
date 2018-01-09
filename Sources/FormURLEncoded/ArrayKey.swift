struct ArrayKey {
    let index: Int
    init(_ index: Int) {
        self.index = index
    }
}

extension ArrayKey: CodingKey {
    var stringValue: String { return String(index) }
    init?(stringValue: String) { fatalError() }
    var intValue: Int? { return index }
    init?(intValue: Int) { fatalError() }
}
