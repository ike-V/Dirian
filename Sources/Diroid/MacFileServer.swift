import Foundation
import Darwin

struct HTTPError: Error {
    let status: Int
    let message: String
    init(_ status: Int, _ message: String) {
        self.status = status
        self.message = message
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    /// Body bytes that arrived in the same reads as the headers.
    let bodyStart: [UInt8]
}

/// A minimal HTTP/1.1 file server on 127.0.0.1, reached from the phone through `adb reverse`.
///
/// Every request needs the bearer token, and every path is relative to, and confined to, `root`.
///   GET /info                       -> {"name": ...}
///   GET /list?path=                 -> [{"name","dir","size","mtime"}]
///   GET /file?path=                 -> file bytes
///   PUT /file?path=                 -> create (409 if it exists)
///   POST /mkdir?path=
///   POST /rename?path=&to=          -> never overwrites
///   DELETE /file?path=              -> moves to the Trash
final class MacFileServer: @unchecked Sendable {
    static let port: UInt16 = 47615

    private let root: URL
    private let rootPath: String
    private let token: String
    private let lock = NSLock()
    private var running = false

    init(root: URL, token: String) {
        let resolved = root.resolvingSymlinksInPath()
        self.root = resolved
        self.rootPath = resolved.path
        self.token = token
    }

    // MARK: - Lifecycle

    func start() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HTTPError(500, "could not create socket") }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = Self.port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw HTTPError(500, "port \(Self.port) unavailable: \(reason)")
        }

        setRunning(true)
        Thread.detachNewThread { [self] in acceptLoop(fd) }
    }

    func stop() {
        setRunning(false)
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private func setRunning(_ value: Bool) {
        lock.lock()
        running = value
        lock.unlock()
    }

    private func acceptLoop(_ fd: Int32) {
        // Polls so stop() takes effect; closing a listening socket doesn't wake accept().
        while isRunning {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, 500) > 0 else { continue }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }

            var one: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 30, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            DispatchQueue.global().async { self.handle(client) }
        }
        close(fd)
    }

    // MARK: - Request handling

    private func handle(_ fd: Int32) {
        defer { close(fd) }
        guard let request = readRequest(fd) else {
            respond(fd, 400, text: "bad request")
            return
        }
        guard isAuthorized(request) else {
            respond(fd, 401, text: "unauthorized")
            return
        }
        do {
            try route(request, fd)
        } catch let error as HTTPError {
            respond(fd, error.status, text: error.message)
        } catch {
            let mapped = Self.map(error)
            respond(fd, mapped.status, text: mapped.message)
        }
    }

    private func route(_ request: HTTPRequest, _ fd: Int32) throws {
        let relative = request.query["path"] ?? ""
        switch (request.method, request.path) {
        case ("GET", "/info"):
            let name = FileManager.default.displayName(atPath: rootPath)
            respondJSON(fd, ["name": name])

        case ("GET", "/list"):
            respondJSON(fd, try list(try resolve(relative)))

        case ("GET", "/file"):
            try sendFile(try resolve(relative), to: fd)

        case ("PUT", "/file"):
            try receiveFile(try resolve(relative), request: request, from: fd)
            respond(fd, 200, text: "ok")

        case ("POST", "/mkdir"):
            try FileManager.default.createDirectory(at: try resolve(relative), withIntermediateDirectories: false)
            respond(fd, 200, text: "ok")

        case ("POST", "/rename"):
            guard let target = request.query["to"] else { throw HTTPError(400, "missing 'to'") }
            // moveItem refuses to overwrite an existing destination.
            try FileManager.default.moveItem(at: try resolve(relative), to: try resolve(target))
            respond(fd, 200, text: "ok")

        case ("DELETE", "/file"):
            guard !relative.split(separator: "/").isEmpty else { throw HTTPError(403, "cannot delete the shared folder") }
            try FileManager.default.trashItem(at: try resolve(relative), resultingItemURL: nil)
            respond(fd, 200, text: "ok")

        default:
            throw HTTPError(404, "no such endpoint")
        }
    }

    private func list(_ directory: URL) throws -> [[String: Any]] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
        return urls.compactMap { url in
            let name = url.lastPathComponent
            if name == ".DS_Store" { return nil }
            // Hide symlinks that lead outside the shared folder; they can't be opened anyway.
            let real = url.resolvingSymlinksInPath().path
            guard real == rootPath || real.hasPrefix(rootPath + "/") else { return nil }
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let values = try? url.resourceValues(forKeys: Set(keys))
            return [
                "name": name,
                "dir": isDirectory.boolValue,
                "size": values?.fileSize ?? 0,
                "mtime": Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0),
            ]
        }
    }

    private func sendFile(_ url: URL, to fd: Int32) throws {
        let file = open(url.path, O_RDONLY)
        guard file >= 0 else { throw Self.map(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)) }
        defer { close(file) }

        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw HTTPError(400, "not a regular file")
        }
        writeAll(fd, Array("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(info.st_size)\r\nConnection: close\r\n\r\n".utf8))

        var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        while true {
            let n = read(file, &buffer, buffer.count)
            if n <= 0 { break }
            if !writeAll(fd, Array(buffer[0..<n])) { break }
        }
    }

    private func receiveFile(_ destination: URL, request: HTTPRequest, from fd: Int32) throws {
        guard let length = Int(request.headers["content-length"] ?? ""), length >= 0 else {
            throw HTTPError(411, "content-length required")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw HTTPError(409, "already exists")
        }

        // Written beside the destination, then renamed, so a dropped connection leaves no partial file.
        let partial = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).diroid-part")
        guard FileManager.default.createFile(atPath: partial.path, contents: nil) else {
            throw HTTPError(404, "cannot create file")
        }
        do {
            let handle = try FileHandle(forWritingTo: partial)
            var remaining = length
            let first = request.bodyStart.prefix(remaining)
            try handle.write(contentsOf: Data(first))
            remaining -= first.count

            var buffer = [UInt8](repeating: 0, count: 256 * 1024)
            while remaining > 0 {
                let n = recv(fd, &buffer, min(buffer.count, remaining), 0)
                guard n > 0 else { throw HTTPError(400, "upload interrupted") }
                try handle.write(contentsOf: Data(buffer[0..<n]))
                remaining -= n
            }
            try handle.close()
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    // MARK: - Paths and auth

    /// Maps a client path (relative to the shared folder) to a file URL, rejecting anything
    /// that would leave the folder, including through symlinks.
    private func resolve(_ relative: String) throws -> URL {
        var url = root
        for part in relative.split(separator: "/") where part != "." {
            if part == ".." { throw HTTPError(400, "bad path") }
            url.appendPathComponent(String(part))
        }
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path) {
            probe.deleteLastPathComponent()
        }
        let real = probe.resolvingSymlinksInPath().path
        guard real == rootPath || real.hasPrefix(rootPath + "/") else {
            throw HTTPError(403, "outside the shared folder")
        }
        return url
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        let given = Array((request.headers["authorization"] ?? "").utf8)
        let expected = Array("Bearer \(token)".utf8)
        guard given.count == expected.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(given, expected) { difference |= a ^ b }
        return difference == 0
    }

    private static func map(_ error: Error) -> HTTPError {
        let ns = error as NSError
        switch (ns.domain, ns.code) {
        case (NSCocoaErrorDomain, NSFileNoSuchFileError), (NSCocoaErrorDomain, NSFileReadNoSuchFileError),
             (NSPOSIXErrorDomain, Int(ENOENT)):
            return HTTPError(404, "not found")
        case (NSCocoaErrorDomain, NSFileWriteFileExistsError), (NSPOSIXErrorDomain, Int(EEXIST)):
            return HTTPError(409, "already exists")
        case (NSCocoaErrorDomain, NSFileReadNoPermissionError), (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
             (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)):
            return HTTPError(403, "permission denied")
        default:
            return HTTPError(500, ns.localizedDescription)
        }
    }

    // MARK: - HTTP framing

    private func readRequest(_ fd: Int32) -> HTTPRequest? {
        var data = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 8192)
        var headerEnd: Int?
        while headerEnd == nil, data.count < 32 * 1024 {
            let n = recv(fd, &buffer, buffer.count, 0)
            if n <= 0 { return nil }
            data.append(contentsOf: buffer[0..<n])
            headerEnd = data.firstRange(of: [13, 10, 13, 10])?.upperBound
        }
        guard let headerEnd else { return nil }

        let head = String(decoding: data[0..<headerEnd - 4], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2, let components = URLComponents(string: String(requestLine[1])) else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }

        return HTTPRequest(
            method: String(requestLine[0]),
            path: components.path,
            query: query,
            headers: headers,
            bodyStart: Array(data[headerEnd...])
        )
    }

    @discardableResult
    private func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBufferPointer { send(fd, $0.baseAddress! + offset, bytes.count - offset, 0) }
            if n <= 0 { return false }
            offset += n
        }
        return true
    }

    private func respond(_ fd: Int32, _ status: Int, text: String) {
        respond(fd, status, contentType: "text/plain; charset=utf-8", body: Array(text.utf8))
    }

    private func respondJSON(_ fd: Int32, _ object: Any) {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("[]".utf8)
        respond(fd, 200, contentType: "application/json", body: [UInt8](body))
    }

    private func respond(_ fd: Int32, _ status: Int, contentType: String, body: [UInt8]) {
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        writeAll(fd, Array(head.utf8) + body)
    }
}
