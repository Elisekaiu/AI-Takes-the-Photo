import Foundation

struct CameraLine: Identifiable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case user, companion }
    var id = UUID()
    let role: Role
    let text: String
}

struct CameraDecision: Decodable, Sendable {
    enum Action: String, Decodable, Sendable { case CAPTURE, WAIT }
    let action: Action
    let say: String
}

/// 你的 AI 可以是 OpenAI、Codex Runtime、自己的 Agent，甚至一个本地小模型。
/// 只要实现这个小协议，就能替换拍摄决策的来源。
protocol CameraDirector: Sendable {
    func respond(imageJPEG: Data?, message: String?, recent: [CameraLine],
                 hasPhoto: Bool, sessionID: UUID) async throws -> CameraDecision
    func beginSession(_ sessionID: UUID, shortMainContext: String?) async throws
    func finishSession(_ sessionID: UUID, photosSaved: Int) async throws -> CameraCheckpoint?
}

// 本地演示与开发者自己的 Director 不需要先实现后端生命周期。
// 使用 HTTPDirector 后，开始/结束会自动接通参考后端的上下文接口。
extension CameraDirector {
    func beginSession(_ sessionID: UUID, shortMainContext: String?) async throws {}
    func finishSession(_ sessionID: UUID, photosSaved: Int) async throws -> CameraCheckpoint? { nil }
}

/// 下载后不用服务器就能体验相机和“自动快门”的演示逻辑。
/// 它是明确标注的本地规则示例，**不冒充视觉大模型**。
struct LocalDemoDirector: CameraDirector {
    func respond(imageJPEG: Data?, message: String?, recent: [CameraLine],
                 hasPhoto: Bool, sessionID: UUID) async throws -> CameraDecision {
        try await Task.sleep(for: .milliseconds(420))
        if let message, !message.isEmpty {
            let wantsShot = message.contains("拍") && imageJPEG != nil && !hasPhoto
            return .init(action: wantsShot ? .CAPTURE : .WAIT,
                         say: wantsShot ? "好呀！我来按下这一张。" : "在呢。想留住这一幕，就让镜头多停一会儿吧。")
        }
        guard imageJPEG != nil else { return .init(action: .WAIT, say: "你举起相机，我就在旁边。") }
        return .init(action: hasPhoto ? .WAIT : .CAPTURE,
                     say: hasPhoto ? "这张已经留下来了，我们再慢慢看看。" : "我想把这一刻留住。咔嚓！")
    }
}

/// 一个极小的远程适配器。密钥由你自己的 HTTPS 后端保管，App 不含模型 API Key。
struct HTTPDirector: CameraDirector {
    let endpoint: URL
    let accessToken: String

    enum ClientError: LocalizedError {
        case invalidEndpoint, server(Int), malformedReply
        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return "请填写自己的 HTTPS 相机服务地址。"
            case .server(let code): return "视觉服务暂时没接上（HTTP \(code)）。"
            case .malformedReply: return "视觉服务返回了不认识的格式。"
            }
        }
    }

    private func sessionURL(_ operation: String) throws -> URL {
        guard endpoint.scheme?.lowercased() == "https",
              endpoint.path.hasSuffix("/decide") else { throw ClientError.invalidEndpoint }
        var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        let prefix = String(endpoint.path.dropLast("decide".count))
        parts?.path = prefix + "session/" + operation
        guard let url = parts?.url else { throw ClientError.invalidEndpoint }
        return url
    }

    private func sessionRequest<Body: Encodable>(_ operation: String, body: Body) async throws -> Data {
        var request = URLRequest(url: try sessionURL(operation))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, reply) = try await URLSession.shared.data(for: request)
        guard (reply as? HTTPURLResponse)?.statusCode == 200 else {
            throw ClientError.server((reply as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    func beginSession(_ sessionID: UUID, shortMainContext: String?) async throws {
        struct Request: Encodable { let sessionId: String; let mainContext: String }
        _ = try await sessionRequest("start", body: Request(
            sessionId: sessionID.uuidString.lowercased(),
            mainContext: String((shortMainContext ?? "").prefix(600))
        ))
    }

    func finishSession(_ sessionID: UUID, photosSaved: Int) async throws -> CameraCheckpoint? {
        struct Request: Encodable { let sessionId: String; let photosSaved: Int }
        struct Envelope: Decodable { let checkpoint: CameraCheckpoint? }
        let data = try await sessionRequest("end", body: Request(
            sessionId: sessionID.uuidString.lowercased(),
            photosSaved: max(0, min(40, photosSaved))
        ))
        return try JSONDecoder().decode(Envelope.self, from: data).checkpoint
    }

    func respond(imageJPEG: Data?, message: String?, recent: [CameraLine],
                 hasPhoto: Bool, sessionID: UUID) async throws -> CameraDecision {
        guard endpoint.scheme?.lowercased() == "https" else { throw ClientError.invalidEndpoint }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 55
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !accessToken.isEmpty { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }

        struct RequestLine: Encodable { let role: String; let text: String }
        struct Payload: Encodable {
            let sessionId: String
            let imageBase64: String?
            let message: String?
            let hasPhoto: Bool
            let recent: [RequestLine]
        }
        let payload = Payload(
            sessionId: sessionID.uuidString.lowercased(),
            imageBase64: imageJPEG?.base64EncodedString(),
            message: message.map { String($0.prefix(300)) },
            hasPhoto: hasPhoto,
            recent: recent.suffix(6).map { .init(role: $0.role.rawValue, text: String($0.text.prefix(180))) }
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            throw ClientError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let decision = try? JSONDecoder().decode(CameraDecision.self, from: data),
              !decision.say.isEmpty, decision.say.count <= 220 else { throw ClientError.malformedReply }
        // 只有拿到这次真实画面的情况下，才能自主按快门。
        return CameraDecision(action: imageJPEG == nil ? .WAIT : decision.action, say: decision.say)
    }
}
