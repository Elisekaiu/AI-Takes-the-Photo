import Foundation

/// 一次相机会话结束后带回来的小纸条，只有文字和数字，不含图片。
/// 任何现有聊天 App 都可以选择接收它，也可以完全忽略。
struct CameraCheckpoint: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let createdAt: String
    let expiresAt: String
    let framesReviewed: Int
    let photosSaved: Int
    let textTurns: Int
    let summary: String

    var isFresh: Bool {
        guard let date = ISO8601DateFormatter().date(from: expiresAt) else { return false }
        return date > Date()
    }
}

/// 给已有聊天或电话使用的“一次性接续”。
/// 只有在主 Agent 成功处理完消息后，才调用 acknowledge；失败时保留。
@MainActor
final class CameraContextInbox {
    struct Receipt {
        let ids: [String]
        let text: String
    }

    private var pending: [CameraCheckpoint] = []

    func offer(_ checkpoint: CameraCheckpoint) {
        guard checkpoint.isFresh else { return }
        pending.removeAll(where: { $0.id == checkpoint.id })
        pending.append(checkpoint)
        pending = Array(pending.suffix(2))
    }

    func peekForNextTurn() -> Receipt? {
        pending.removeAll(where: { !$0.isFresh })
        guard !pending.isEmpty else { return nil }
        let summaries = pending.map { String($0.summary.prefix(430)) }.joined(separator: "\n")
        return Receipt(
            ids: pending.map(\.id),
            text: "[最近的相机陪伴｜只含简短文字，不代表正在看实时画面]\n" +
                summaries + "\n[/最近的相机陪伴]\n"
        )
    }

    func acknowledgeAfterSuccess(_ receipt: Receipt) {
        let finished = Set(receipt.ids)
        pending.removeAll(where: { finished.contains($0.id) })
    }
}
