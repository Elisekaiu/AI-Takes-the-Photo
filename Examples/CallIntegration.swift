import SwiftUI

// 这是集成示意，不是第二套电话系统。请复制到你自己的 VoIP App。
// 你的 WebRTC / CallKit / TTS / STT 继续管理音频和通话状态。
struct ExistingVoiceCallView: View {
    @State private var showCamera = false

    var body: some View {
        ZStack {
            // 这里放你已经接通的电话页面。例如 CallKit + WebRTC UI。
            VStack(spacing: 16) {
                Text("正在通话中")
                    .font(.title2)
                Text("声音由原来的电话系统负责")
                    .font(.caption)
                Button("一起拍") { showCamera = true }
            }
            // 正式集成时，可将 CameraStudioView 改成只暴露 CameraPanel，
            // 保持原来的电话 View 始终挂载在下面，避免断开通话。
            if showCamera {
                CameraStudioView()
                    .overlay(alignment: .topTrailing) {
                        Button("回到电话") { showCamera = false }
                            .padding()
                    }
            }
        }
    }
}
