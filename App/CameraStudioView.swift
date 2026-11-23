import SwiftUI

private enum Palette {
    static let night = Color(red: 0.07, green: 0.07, blue: 0.095)
    static let panel = Color(red: 0.105, green: 0.10, blue: 0.14)
    static let cream = Color(red: 0.96, green: 0.94, blue: 0.92)
    static let lilac = Color(red: 0.77, green: 0.74, blue: 0.88)
    static let mint = Color(red: 0.67, green: 0.88, blue: 0.77)
}

/// 这整个 Demo 是 SwiftUI。真实镜头来自 CameraHardware，不需要 WebView。
struct CameraStudioView: View {
    @StateObject private var model = CameraStudioModel()
    /// 宿主传入近期简短文字；独立 Demo 默认为空。
    let initialMainContext: String
    /// 仅在远程视觉会话结束且确有活动时回传一次文字小结。
    let onCheckpoint: ((CameraCheckpoint) -> Void)?

    init(initialMainContext: String = "", onCheckpoint: ((CameraCheckpoint) -> Void)? = nil) {
        self.initialMainContext = initialMainContext
        self.onCheckpoint = onCheckpoint
    }

    @State private var simulateCall = false
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.night.ignoresSafeArea()
            home
            if model.isOpen { cameraPanel.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            model.initialMainContext = String(initialMainContext.prefix(600))
            model.onCheckpoint = onCheckpoint
        }
        .animation(.easeOut(duration: 0.24), value: model.isOpen)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            model.close() // 不用静音音频保活；离开相机即关闭
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack {
                    Image(systemName: "camera.aperture")
                        .foregroundStyle(Palette.mint)
                    Text("AI TAKES THE PHOTO")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.7)
                        .foregroundStyle(Palette.lilac)
                    Spacer()
                    Button { showSettings.toggle() } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Palette.cream)
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("相机与 AI 设置")
                }
                .padding(.top, 28)

                Text("有些瞬间，\n不用等你说拍。")
                    .font(.system(size: 35, weight: .regular, design: .serif))
                    .tracking(-0.3)
                    .foregroundStyle(Palette.cream)
                    .fixedSize(horizontal: false, vertical: true)
                Text("把镜头举起来。你们可以边聊边看，喜欢哪一幕，AI 就能替你按下快门。")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.cream.opacity(0.73))
                    .lineSpacing(5)

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "heart.text.square")
                            .foregroundStyle(Palette.mint)
                        Text(simulateCall ? "通话页面 · UI 演示" : "相机准备好啦")
                            .foregroundStyle(Palette.cream)
                            .font(.system(size: 15, weight: .medium))
                        Spacer()
                        Circle().fill(Palette.mint).frame(width: 7, height: 7)
                    }
                    Text(simulateCall ? "这是布局演示，不会真的拨打电话。接入你自己的 VoIP 后，打开相机的方式完全一样。" : "前后摄切换 · 手动快门 · 自动抓拍 · 一边看一边聊")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.lilac)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.open() } label: {
                        HStack {
                            Text(simulateCall ? "通话中一起拍" : "打开相机")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.night)
                        .padding(16)
                        .background(Palette.cream, in: RoundedRectangle(cornerRadius: 15))
                    }
                }
                .padding(18)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))

                if let checkpoint = model.lastCheckpoint {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("这次拍照的小纸条", systemImage: "text.alignleft")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.mint)
                        Text(checkpoint.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.cream.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("只包含文字，不含画面；可交给你自己的主聊天使用一次。")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.lilac)
                    }
                    .padding(16)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 19))
                }

                Toggle("演示通话中的相机入口", isOn: $simulateCall)
                    .font(.system(size: 13))
                    .tint(Palette.mint)
                    .foregroundStyle(Palette.cream.opacity(0.85))

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.useRemoteAI ? "sparkles" : "gearshape.2")
                        .foregroundStyle(Palette.mint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.useRemoteAI ? "自定义视觉 AI" : "本地演示模式")
                            .font(.system(size: 14, weight: .medium))
                        Text(model.useRemoteAI ? "会使用你配置的 HTTPS 视觉服务。" : "无需账号就能运行相机和自动快门示例。规则演示不等于真正的视觉模型，想让 AI 自己选景可以在设置里接入后端。")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.lilac)
                    }
                }
                .padding(.top, 10)

                if showSettings { settings }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 70)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("连接你自己的 AI")
                .font(.system(size: 17, weight: .medium))
            Toggle("使用远程视觉模型", isOn: $model.useRemoteAI)
                .font(.system(size: 13))
                .tint(Palette.mint)
                .onChange(of: model.useRemoteAI) { _, _ in model.updateConfig() }
            if model.useRemoteAI {
                TextField("https://你的服务地址/api/decide", text: $model.serverAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: model.serverAddress) { _, _ in model.updateConfig() }
                    .font(.system(size: 12))
                    .padding(12)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                SecureField("后端访问令牌（如设置过）", text: $model.sessionToken)
                    .font(.system(size: 12))
                    .padding(12)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                Text("模型密钥只放在你自己的服务端。App 这里填的是可选访问令牌，仅本次打开 App 有效。")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.lilac)
            }
        }
        .padding(17)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var cameraPanel: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Palette.night.opacity(0.54).ignoresSafeArea()
                    .onTapGesture { model.close() }
                VStack(spacing: 9) {
                    HStack(spacing: 10) {
                        Circle().fill(model.isReady ? Palette.mint : Palette.lilac)
                            .frame(width: 6, height: 6)
                        Text("WITH YOU · CAMERA")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(1.5)
                        Spacer()
                        Text(model.useRemoteAI ? "AI 连线模式" : "本地示例")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.lilac)
                        Button { model.close() } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(Palette.cream.opacity(0.85))
                        }
                        .accessibilityLabel("关闭相机")
                    }
                    .padding(.horizontal, 17)
                    .padding(.top, 17)

                    ScrollViewReader { scroll in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                if model.lines.isEmpty {
                                    Text("我想拍的时候，会自己按快门。你也可以随时跟我说话。")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.lilac)
                                        .padding(.vertical, 6)
                                }
                                ForEach(model.lines) { line in
                                    HStack {
                                        if line.role == .user { Spacer(minLength: 30) }
                                        Text(line.text)
                                            .font(.system(size: 12))
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 7)
                                            .background(line.role == .user ? Color.white.opacity(0.12) : Color.white.opacity(0.06),
                                                        in: RoundedRectangle(cornerRadius: 13))
                                            .id(line.id)
                                        if line.role != .user { Spacer(minLength: 30) }
                                    }
                                }
                            }
                        }
                        .onChange(of: model.lines.count) { _, _ in
                            if let id = model.lines.last?.id {
                                withAnimation { scroll.scrollTo(id, anchor: .bottom) }
                            }
                        }
                    }
                    .frame(height: 65)
                    .padding(.horizontal, 17)

                    HStack(spacing: 9) {
                        TextField("和你的 AI 说句话…", text: $model.draft)
                            .font(.system(size: 13))
                            .submitLabel(.send)
                            .onSubmit { model.sendChat() }
                        Button { model.sendChat() } label: {
                            Image(systemName: model.isThinking ? "ellipsis" : "arrow.up.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Palette.lilac)
                        }
                        .disabled(model.isThinking || model.draft.isEmpty)
                    }
                    .padding(12)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 12)

                    ZStack(alignment: .bottom) {
                        if let image = model.latestPhoto {
                            GeometryReader { frame in
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: frame.size.width, height: frame.size.height).clipped()
                            }
                        } else if model.isReady {
                            CameraPreview(session: model.camera.session, front: model.isFront)
                        } else {
                            Rectangle().fill(.black)
                            ProgressView("正在打开镜头")
                        }
                        LinearGradient(colors: [.clear, .black.opacity(0.1), .black.opacity(0.84)],
                                       startPoint: .center, endPoint: .bottom)
                        VStack {
                            HStack {
                                Spacer()
                                if model.latestPhoto == nil {
                                    Button { model.switchLens() } label: {
                                        Image(systemName: "camera.rotate")
                                            .font(.system(size: 19))
                                            .frame(width: 43, height: 43)
                                            .background(.black.opacity(0.55), in: Circle())
                                    }
                                    .accessibilityLabel("切换前后摄像头")
                                }
                            }
                            Spacer()
                            Text(model.tip)
                                .font(.system(size: 13))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 12))
                            HStack {
                                Button { model.latestPhoto == nil ? model.close() : model.nextShot() } label: {
                                    Image(systemName: model.latestPhoto == nil ? "chevron.left" : "arrow.counterclockwise")
                                        .frame(width: 44, height: 44)
                                        .background(.black.opacity(0.5), in: Circle())
                                }
                                Spacer()
                                Button {
                                    if model.latestPhoto == nil { model.capture() }
                                    else { model.saveToAlbum() }
                                } label: {
                                    Image(systemName: model.latestPhoto == nil ? "circle.fill" : "square.and.arrow.down")
                                        .font(.system(size: model.latestPhoto == nil ? 61 : 25))
                                        .foregroundStyle(Palette.cream)
                                        .frame(width: 68, height: 68)
                                        .background(.white.opacity(0.1), in: Circle())
                                }
                                .disabled(!model.isReady)
                                .accessibilityLabel(model.latestPhoto == nil ? "手动按快门" : "保存照片到相册")
                                Spacer()
                                Button { model.autoShutter.toggle() } label: {
                                    Image(systemName: model.autoShutter ? "sparkles" : "sparkle")
                                        .frame(width: 44, height: 44)
                                        .background(.black.opacity(0.5), in: Circle())
                                }
                                .accessibilityLabel("切换自动快门")
                            }
                            .padding(.top, 14)
                        }
                        .padding(16)
                    }
                    .frame(height: max(295, min(proxy.size.height * 0.49, 440)))
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .padding(.horizontal, 7)

                    if let notice = model.notice {
                        Text(notice).font(.system(size: 12))
                            .foregroundStyle(Palette.lilac)
                            .padding(.horizontal, 14)
                    }
                    Text("只有打开相机才会取样 · 关闭后停止 · 照片先保存在本机")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.lilac.opacity(0.8))
                        .padding(.bottom, 12)
                }
                .foregroundStyle(Palette.cream)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 29))
                .overlay(RoundedRectangle(cornerRadius: 29).strokeBorder(.white.opacity(0.12)))
                .padding(.horizontal, 12)
                .padding(.bottom, 13)
            }
        }
    }
}
