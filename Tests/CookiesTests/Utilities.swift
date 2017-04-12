import HTTP
import URI

extension Request {
    convenience init() {
        let uri = URI(hostname: "test", path: "/")
        self.init(method: .get, uri: uri)
    }
}

extension Response {
    convenience init() {
        self.init(status: .ok)
    }
}
