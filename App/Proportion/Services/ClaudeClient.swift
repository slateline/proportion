import Foundation

/// A minimal Messages API client over URLSession. Swift has no official
/// Anthropic SDK, so this speaks the raw HTTP shape directly.
///
/// The app only ever needs one interaction pattern: send content, get back a
/// single structured tool call validated against a strict JSON schema. That
/// is what `invokeTool` does. Adaptive thinking is left on with a per-call
/// effort level, and server-side refusal fallbacks are enabled so a rare
/// policy decline is retried on a fallback model inside the same request.
struct ClaudeClient: Sendable {
    var apiKey: String
    var model: String
    var session: URLSession
    var endpoint: URL

    init(
        apiKey: String,
        model: String,
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
        self.endpoint = endpoint
    }

    enum Effort: String, Sendable {
        case low, medium, high
    }

    enum Content: Sendable {
        case text(String)
        case jpeg(Data)

        var block: [String: Any] {
            switch self {
            case .text(let text):
                return ["type": "text", "text": text]
            case .jpeg(let data):
                return [
                    "type": "image",
                    "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()],
                ]
            }
        }
    }

    /// `@unchecked` because the schema dictionary is built once from literals
    /// and never mutated; it is safe to share across tasks.
    struct Tool: @unchecked Sendable {
        var name: String
        var description: String
        /// A JSON Schema object. Strict mode requires `additionalProperties: false`
        /// and every property listed in `required`; use `Schema` to build it.
        var inputSchema: [String: Any]

        var definition: [String: Any] {
            ["name": name, "description": description, "input_schema": inputSchema, "strict": true]
        }
    }

    enum ClientError: LocalizedError {
        case http(status: Int, message: String)
        case refused(String?)
        case noToolCall(text: String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .http(let status, let message): return "Claude API error \(status): \(message)"
            case .refused(let explanation): return explanation ?? "The request was declined."
            case .noToolCall(let text): return text.isEmpty ? "The model returned no structured result." : text
            case .malformedResponse: return "Unexpected response from the model."
            }
        }
    }

    /// Sends `content` and returns the input of the single `tool` call the
    /// model makes, decoded as `T`.
    func invokeTool<T: Decodable>(
        _ type: T.Type,
        system: String,
        content: [Content],
        tool: Tool,
        effort: Effort = .medium,
        maxTokens: Int = 16000
    ) async throws -> T {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": effort.rawValue],
            "fallbacks": "default",
            "tools": [tool.definition],
            "tool_choice": ["type": "auto"],
            "messages": [["role": "user", "content": content.map(\.block)]],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String } ?? String(decoding: data, as: UTF8.self)
            throw ClientError.http(status: http.statusCode, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.malformedResponse
        }
        if json["stop_reason"] as? String == "refusal" {
            let explanation = (json["stop_details"] as? [String: Any])?["explanation"] as? String
            throw ClientError.refused(explanation)
        }

        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let call = blocks.first(where: { $0["type"] as? String == "tool_use" && $0["name"] as? String == tool.name }),
              let input = call["input"] else {
            let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            throw ClientError.noToolCall(text: text)
        }
        let inputData = try JSONSerialization.data(withJSONObject: input)
        return try JSONDecoder().decode(T.self, from: inputData)
    }
}

/// Helpers for writing strict JSON schemas as Swift dictionaries.
enum Schema {
    static func object(_ properties: [String: Any], description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": properties.keys.sorted(),
            "additionalProperties": false,
        ]
        if let description { schema["description"] = description }
        return schema
    }

    static func string(_ description: String, nullable: Bool = false, values: [String]? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": nullable ? ["string", "null"] : "string", "description": description]
        if let values { schema["enum"] = nullable ? values + [NSNull()] as [Any] : values }
        return schema
    }

    static func number(_ description: String, nullable: Bool = false) -> [String: Any] {
        ["type": nullable ? ["number", "null"] : "number", "description": description]
    }

    static func integer(_ description: String, nullable: Bool = false) -> [String: Any] {
        ["type": nullable ? ["integer", "null"] : "integer", "description": description]
    }

    static func boolean(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    static func array(of item: [String: Any], description: String) -> [String: Any] {
        ["type": "array", "items": item, "description": description]
    }
}
