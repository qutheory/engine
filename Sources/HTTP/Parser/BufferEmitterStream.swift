/// use push stream?
//import Async
//import Bits
//import Foundation
//
//internal final class ByteBufferPushStream: Async.OutputStream {
//    typealias Output = ByteBuffer
//
//    var downstreamDemand: UInt
//    var downstream: AnyInputStream<ByteBuffer>?
//    var backlog = [Data]()
//    var writing: Data?
//    var flushedBacklog: Int
//    var closed: Bool
//
//    init() {
//        downstreamDemand = 0
//        flushedBacklog = 0
//        closed = false
//    }
//
//    func eof() {
//        if backlog.count == 0 {
//            downstream?.close()
//        }
//
//        self.closed = true
//    }
//
//    func output<S>(to inputStream: S) where S : Async.InputStream, Output == S.Input {
//        self.downstream = AnyInputStream(inputStream)
//    }
//
//    func push(_ buffer: ByteBuffer) {
//        flushBacklog()
//
//        if downstreamDemand > 0 {
//            downstreamDemand -= 1
//            downstream?.next(buffer) {
//                // ignore, fixme
//            }
//        } else {
//            backlog.append(Data(buffer: buffer))
//        }
//
//        if closed && backlog.count == 0 {
//            downstream?.close()
//        }
//    }
//
//    fileprivate func flushBacklog() {
//        defer {
//            backlog.removeFirst(flushedBacklog)
//            flushedBacklog = 0
//
//            if closed && backlog.count == 0 {
//                downstream?.close()
//            }
//        }
//
//        while backlog.count - flushedBacklog > 0, downstreamDemand > 0 {
//            downstreamDemand -= 1
//            let data = backlog[flushedBacklog]
//            flushedBacklog += 1
//            self.writing = data
//
//            data.withByteBuffer { buffer in
//                self.downstream?.next(buffer) {
//                    // ignore, fixme
//                }
//            }
//        }
//    }
//}
