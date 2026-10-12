import Foundation
import Network

@MainActor
final class LocalHTTPServer: ObservableObject {
    @Published private(set) var baseURL: URL?
    @Published private(set) var errorMessage: String?

    private let queue = DispatchQueue(label: "com.local.body3d.http", qos: .userInitiated)
    private var listener: NWListener?
    nonisolated(unsafe) private var rootDirectory: URL?

    func start() {
        guard listener == nil else { return }
        guard let root = locateWebRoot() else {
            errorMessage = "找不到 Contents/Resources/Web。"
            return
        }
        rootDirectory = root.standardizedFileURL

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port else { return }
                    Task { @MainActor in
                        self.baseURL = URL(string: "http://127.0.0.1:\(port.rawValue)/")
                    }
                case .failed(let error):
                    Task { @MainActor in self.errorMessage = error.localizedDescription }
                    listener.cancel()
                default:
                    break
                }
            }
            listener.start(queue: queue)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func locateWebRoot() -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let packaged = resourceURL.appendingPathComponent("Web", isDirectory: true)
            if FileManager.default.fileExists(atPath: packaged.path) { return packaged }
        }

        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Body3DMac/Resources/Web", isDirectory: true)
        return FileManager.default.fileExists(atPath: development.path) ? development : nil
    }

    private nonisolated func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private nonisolated func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var requestData = accumulated
            if let data { requestData.append(data) }

            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                self.respond(to: requestData, on: connection)
            } else if error == nil && requestData.count < 65_536 {
                self.receiveRequest(on: connection, accumulated: requestData)
            } else {
                connection.cancel()
            }
        }
    }

    private nonisolated func respond(to requestData: Data, on connection: NWConnection) {
        guard
            let request = String(data: requestData, encoding: .utf8),
            let firstLine = request.components(separatedBy: "\r\n").first
        else {
            send(status: "400 Bad Request", body: Data(), contentType: "text/plain", on: connection)
            return
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
            send(status: "405 Method Not Allowed", body: Data(), contentType: "text/plain", on: connection)
            return
        }

        let requestPath = String(parts[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        let decodedPath = requestPath.removingPercentEncoding ?? requestPath
        let relativePath = decodedPath == "/" ? "index.html" : String(decodedPath.drop(while: { $0 == "/" }))

        guard
            !relativePath.contains(".."),
            !relativePath.hasPrefix("/"),
            let root = rootDirectory
        else {
            send(status: "403 Forbidden", body: Data(), contentType: "text/plain", on: connection)
            return
        }

        let fileURL = root.appendingPathComponent(relativePath).standardizedFileURL
        guard fileURL.path.hasPrefix(root.path), let fileData = try? Data(contentsOf: fileURL) else {
            send(status: "404 Not Found", body: Data("Not found".utf8), contentType: "text/plain; charset=utf-8", on: connection)
            return
        }

        let body = parts[0] == "HEAD" ? Data() : fileData
        send(
            status: "200 OK",
            body: body,
            declaredLength: fileData.count,
            contentType: Self.mimeType(for: fileURL.pathExtension),
            on: connection
        )
    }

    private nonisolated func send(
        status: String,
        body: Data,
        declaredLength: Int? = nil,
        contentType: String,
        on connection: NWConnection
    ) {
        let header = """
        HTTP/1.1 \(status)\r
        Content-Length: \(declaredLength ?? body.count)\r
        Content-Type: \(contentType)\r
        Access-Control-Allow-Origin: *\r
        Cache-Control: public, max-age=31536000\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated static func mimeType(for extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}
