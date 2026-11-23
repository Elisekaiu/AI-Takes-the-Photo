import SwiftUI

/// 提供给已有聊天/电话 App 参考的桥接方式。
/// 这个文件在 Examples/ 下，不参与独立相机 Demo 的构建。
/// `MyExistingChatAPI` 只表示你已经在使用的主聊天接口。
protocol MyExistingChatAPI {
    func reply(to userMessage: String, withInternalContext: String?) async throws -> String
}

@MainActor
final class CameraAndChatBridge: ObservableObject {
    let cameraInbox = CameraContextInbox()

    /// 你自己的主聊天可以把最多几句近期内容合成一小段文字传给相机。
    var shortRecentChat: String { "我们刚刚聊到夕阳很漂亮。" }

    func cameraFinished(_ checkpoint: CameraCheckpoint) {
        cameraInbox.offer(checkpoint)
    }

    func ordinaryChatTurn(_ message: String, through api: any MyExistingChatAPI) async throws -> String {
        // peek 不会消耗上下文。失败时下一次仍能读到这张小纸条。
        let receipt = cameraInbox.peekForNextTurn()
        let result = try await api.reply(to: message, withInternalContext: receipt?.text)
        if let receipt {
            cameraInbox.acknowledgeAfterSuccess(receipt)
        }
        return result
    }
}

struct CompanionAppWithCameraExample: View {
    @StateObject private var bridge = CameraAndChatBridge()
    @State private var showCamera = false

    var body: some View {
        ZStack {
            VStack {
                Text("这里放你原本的聊天或电话界面")
                Button("一起拍") { showCamera = true }
            }
            if showCamera {
                CameraStudioView(
                    initialMainContext: bridge.shortRecentChat,
                    onCheckpoint: { bridge.cameraFinished($0) }
                )
            }
        }
    }
}
