import Foundation

/// 纯 Foundation 测试，可在 Mac/Linux 上独立跑，不必打开相机。
@main
struct ContextInboxTests {
    @MainActor static func main() {
        let current = Date()
        let fmt = ISO8601DateFormatter()
        let checkpoint = CameraCheckpoint(
            id: UUID().uuidString.lowercased(),
            createdAt: fmt.string(from: current),
            expiresAt: fmt.string(from: current.addingTimeInterval(7200)),
            framesReviewed: 2,
            photosSaved: 1,
            textTurns: 1,
            summary: "刚刚一起拍了小熊玩偶，拍成了一张。"
        )
        let inbox = CameraContextInbox()
        inbox.offer(checkpoint)
        guard let first = inbox.peekForNextTurn() else { fatalError("missing camera note") }
        precondition(first.text.contains("小熊玩偶"))
        precondition(inbox.peekForNextTurn() != nil, "failed main request must preserve note")
        inbox.acknowledgeAfterSuccess(first)
        precondition(inbox.peekForNextTurn() == nil, "note should be consumed once")

        inbox.offer(checkpoint)
        inbox.offer(checkpoint)
        precondition(inbox.peekForNextTurn()?.ids.count == 1, "duplicates coalesce")
        inbox.acknowledgeAfterSuccess(inbox.peekForNextTurn()!)
        let expired = CameraCheckpoint(
            id: UUID().uuidString.lowercased(),
            createdAt: fmt.string(from: current.addingTimeInterval(-20000)),
            expiresAt: fmt.string(from: current.addingTimeInterval(-3600)),
            framesReviewed: 5, photosSaved: 0, textTurns: 0, summary: "已经过期"
        )
        inbox.offer(expired)
        precondition(inbox.peekForNextTurn() == nil)
        print("PASS: short camera context is bounded, expires and is acknowledged only after success")
    }
}
