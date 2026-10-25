import Foundation

public final class SimpleVectorizerMCPServer {
    let transport: Transport
    let apiBase: String
    let version: String

    public init(transport: @escaping Transport, apiBase: String = "http://127.0.0.1:17940", version: String = "0.7.8") {
        self.transport = transport
        self.apiBase = apiBase
        self.version = version
    }

    public func run() {
        while let line = readLine(strippingNewline: true) {
            if let response = handle(line: line) { Self.write(response) }
        }
    }

    static func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    public func handle(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let message = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]])
        }
        guard let method = message["method"] as? String else { return nil }
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        var result: [String: Any]?
        var failure: (code: Int, message: String)?

        switch method {
        case "initialize":
            result = [
                "protocolVersion": params["protocolVersion"] as? String ?? "2024-11-05",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "simplevectorizer", "version": version],
                "instructions": "Controls SimpleVectorizer, the native macOS bitmap-to-SVG line-art vectorizer for AxiDraw plotters (Neural Engine ridge & Vision contour extraction, Steger sub-pixel centerline, Schneider cubic Bézier fitting, multi-pen stroke width clustering, 2-opt travel optimization). Call simplevectorizer_state first; load images or presets with simplevectorizer_open; adjust parameters with simplevectorizer_set_params; export SVG with simplevectorizer_export_svg; inspect visually with simplevectorizer_snapshot.",
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": simpleVectorizerToolDefinitions]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            guard simpleVectorizerToolDefinitions.contains(where: { $0["name"] as? String == name }) else {
                failure = (-32602, "unknown tool: \(name)")
                break
            }
            do {
                result = try callTool(name, params["arguments"] as? [String: Any] ?? [:])
            } catch {
                result = ["content": [["type": "text", "text": "\(error)"]], "isError": true]
            }
        default:
            failure = (-32601, "method not found: \(method)")
        }

        if let result { return encode(["jsonrpc": "2.0", "id": id, "result": result]) }
        let f = failure ?? (-32601, "method not found: \(method)")
        return encode(["jsonrpc": "2.0", "id": id, "error": ["code": f.code, "message": f.message]])
    }

    func encode(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func textResult(_ response: APIResponse) -> [String: Any] {
        ["content": [["type": "text", "text": String(decoding: response.data, as: UTF8.self)]], "isError": response.status >= 400]
    }

    func imageResult(_ response: APIResponse, caption: String) -> [String: Any] {
        guard response.status == 200, !response.contentType.lowercased().contains("json") else { return textResult(response) }
        let mime = response.contentType.lowercased().hasPrefix("image/") ? String(response.contentType.split(separator: ";")[0]) : "image/png"
        return [
            "content": [
                ["type": "image", "data": response.data.base64EncodedString(), "mimeType": mime],
                ["type": "text", "text": caption],
            ]
        ]
    }

    func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    func call(_ method: String, _ path: String, body: Any? = nil) throws -> APIResponse {
        try transport(method, "/v1" + path, try body.map(json))
    }

    func callTool(_ name: String, _ args: [String: Any]) throws -> [String: Any] {
        switch name {
        case "simplevectorizer_state":
            return textResult(try call("GET", "/state"))
        case "simplevectorizer_help":
            return textResult(try call("GET", "/help"))
        case "simplevectorizer_open":
            return textResult(try call("POST", "/open", body: args))
        case "simplevectorizer_set_params":
            return textResult(try call("POST", "/params", body: args))
        case "simplevectorizer_export_svg":
            return textResult(try call("POST", "/export", body: args))
        case "simplevectorizer_snapshot":
            let view = (args["view"] as? String) ?? ""
            let suffix = view.isEmpty ? "" : "?view=\(view)"
            let response = try call("GET", "/snapshot.png" + suffix)
            return imageResult(response, caption: "Snapshot of the SimpleVectorizer window.")
        default:
            throw ProxyError.badArguments("unknown tool \(name)")
        }
    }
}
