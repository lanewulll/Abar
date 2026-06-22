import AbarOverlayCore
import Darwin
import Foundation

final class AbarLocalEventServer: @unchecked Sendable {
    private let port: UInt16
    private let store: AbarEventStore
    private let onEvent: @MainActor @Sendable () -> Void
    private let queue = DispatchQueue(label: "dev.abar.native-overlay.local-server")
    private var socketFD: Int32 = -1
    private var isRunning = false

    init(port: UInt16 = 3987, store: AbarEventStore, onEvent: @escaping @MainActor @Sendable () -> Void) {
        self.port = port
        self.store = store
        self.onEvent = onEvent
    }

    func start() {
        queue.async { [weak self] in
            self?.run()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            isRunning = false
            if socketFD >= 0 {
                Darwin.close(socketFD)
                socketFD = -1
            }
        }
    }

    private func run() {
        guard socketFD < 0 else { return }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            NSLog("[AbarNativeOverlay] server socket failed")
            return
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindStatus = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0 else {
            NSLog("[AbarNativeOverlay] server bind failed on 127.0.0.1:%d: %s", port, strerror(errno))
            Darwin.close(fd)
            return
        }

        guard listen(fd, 8) == 0 else {
            NSLog("[AbarNativeOverlay] server listen failed: %s", strerror(errno))
            Darwin.close(fd)
            return
        }

        socketFD = fd
        isRunning = true
        NSLog("[AbarNativeOverlay] local event server listening on 127.0.0.1:%d", port)

        while isRunning {
            let client = accept(fd, nil, nil)
            if client >= 0 {
                handleClient(client)
                Darwin.close(client)
            } else if errno != EBADF {
                NSLog("[AbarNativeOverlay] server accept failed: %s", strerror(errno))
            }
        }
    }

    private func handleClient(_ client: Int32) {
        do {
            let request = try readRequest(client)
            if request.method == "GET", request.path == "/health" {
                writeResponse(client, status: 200, body: #"{"ok":true,"service":"abar"}"#)
                return
            }
            if request.method == "POST", request.path == "/events" {
                let event = try AbarHookEventNormalizer.normalize(data: request.body)
                try store.insertEvent(event)
                let onEvent = onEvent
                Task { @MainActor in onEvent() }
                writeResponse(client, status: 202, body: #"{"ok":true}"#)
                return
            }
            writeResponse(client, status: 404, body: #"{"ok":false,"error":"Not found"}"#)
        } catch {
            let escaped = String(describing: error).replacingOccurrences(of: "\"", with: "\\\"")
            writeResponse(client, status: 400, body: #"{"ok":false,"error":"\#(escaped)"}"#)
        }
    }

    private func readRequest(_ client: Int32) throws -> HTTPRequest {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var headerEnd: Range<Data.Index>?
        var contentLength = 0

        while data.count < 1_048_576 {
            let count = Darwin.read(client, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)

            if headerEnd == nil, let range = data.range(of: Data("\r\n\r\n".utf8)) {
                headerEnd = range
                let headerData = data[..<range.lowerBound]
                let headerText = String(decoding: headerData, as: UTF8.self)
                contentLength = parseContentLength(headerText)
            }

            if let headerEnd, data.count >= headerEnd.upperBound + contentLength {
                let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
                let bodyStart = headerEnd.upperBound
                let bodyEnd = bodyStart + contentLength
                let body = data[bodyStart..<bodyEnd]
                let requestLine = head.components(separatedBy: "\r\n").first ?? ""
                let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
                guard parts.count >= 2 else { throw LocalServerError.badRequest }
                return HTTPRequest(method: parts[0], path: parts[1], body: Data(body))
            }
        }

        throw LocalServerError.badRequest
    }

    private func parseContentLength(_ headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }
        }
        return 0
    }

    private func writeResponse(_ client: Int32, status: Int, body: String) {
        let reason = status == 202 ? "Accepted" : status == 200 ? "OK" : status == 404 ? "Not Found" : "Bad Request"
        let payload = Data(body.utf8)
        let header = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: application/json; charset=utf-8",
            "Cache-Control: no-store",
            "Content-Length: \(payload.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(header.utf8)
        response.append(payload)
        response.withUnsafeBytes { pointer in
            _ = Darwin.write(client, pointer.baseAddress, response.count)
        }
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var body: Data
}

private enum LocalServerError: Error {
    case badRequest
}
