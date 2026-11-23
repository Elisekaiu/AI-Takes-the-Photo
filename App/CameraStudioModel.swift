import AVFoundation
import Foundation
import SwiftUI
import UIKit

/// SwiftUI 只监听这个对象；摄像头仍在私有串行队列中运作。
@MainActor
final class CameraStudioModel: ObservableObject {
    let camera = CameraHardware()

    @Published var isOpen = false
    @Published var isReady = false
    @Published var isFront = false
    @Published var isThinking = false
    @Published var autoShutter = true
    @Published var useRemoteAI = false
    @Published var serverAddress = ""
    @Published var sessionToken = "" // 仅当前运行期间保留；不写入磁盘
    @Published var draft = ""
    @Published var lines: [CameraLine] = []
    @Published var latestPhoto: UIImage?
    @Published var photoCount = 0
    @Published var tip = "你可以带我看任何想看的东西。"
    @Published var notice: String?
    @Published private(set) var lastCheckpoint: CameraCheckpoint?

    /// 集成到自己的主聊天时，提供一段有界的文字背景（最多 600 字）。
    /// 默认空，不会偷偷读取或上传你原本的聊天历史。
    var initialMainContext = ""
    /// 宿主可把结束小结交给主 Agent；Demo 默认只在界面展示。
    var onCheckpoint: ((CameraCheckpoint) -> Void)?

    private var sessionDirector: (any CameraDirector)?
    private var sessionStartTask: Task<Void, Never>?
    private var currentPhoto: PhotoVault.Saved?
    private var currentSession = UUID()
    private var generation = UUID()
    private var lensVersion = 0
    private var activeJob: Task<Void, Never>?
    private var lastSample: (data: Data, signature: [UInt8], at: Date)?

    init() {
        serverAddress = UserDefaults.standard.string(forKey: "demo.serverAddress") ?? ""
        useRemoteAI = UserDefaults.standard.bool(forKey: "demo.useRemote")
        camera.onStarted = { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, self.isOpen else { return }
                self.isReady = value
                if !value { self.notice = "相机暂时没有启动，请检查权限。" }
            }
        }
        camera.onFacing = { [weak self] front in
            Task { @MainActor [weak self] in
                guard let self, self.isOpen else { return }
                self.isFront = front
                self.tip = front ? "前摄准备好了，笑不笑都很好看。" : "后摄准备好啦，继续看看。"
            }
        }
        camera.onSample = { [weak self] data, signature in
            Task { @MainActor [weak self] in
                guard let self, self.isOpen else { return }
                self.lastSample = (data, signature, Date())
                self.observe(data, signature: signature)
            }
        }
        camera.onPhoto = { [weak self] bytes in
            Task { @MainActor [weak self] in self?.photoDidFinish(bytes) }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        currentSession = UUID()
        generation = UUID()
        lensVersion = 0
        latestPhoto = nil
        currentPhoto = nil
        photoCount = 0
        lines = []
        draft = ""
        notice = nil
        tip = "我在这儿，镜头交给我吧。"
        // 相机视觉请求与主聊天线程独立：开始时只给短文字，绝不附带历史图片。
        let sessionID = currentSession
        let intro = String(initialMainContext.prefix(600))
        sessionDirector = try? director()
        if let selected = sessionDirector {
            sessionStartTask = Task { [weak self] in
                do { try await selected.beginSession(sessionID, shortMainContext: intro) }
                catch {
                    guard let self, self.isOpen, self.currentSession == sessionID else { return }
                    // 视觉接口支持按需自动创建会话，所以不中断相机。
                    self.notice = "短期接续暂时没连上，相机仍可以照常使用。"
                }
            }
        }
        Task { [weak self] in
            guard let self else { return }
            let permitted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: permitted = true
            case .notDetermined: permitted = await AVCaptureDevice.requestAccess(for: .video)
            default: permitted = false
            }
            guard self.isOpen else { return }
            if permitted { self.camera.start() }
            else { self.notice = "请到 iPhone 设置里允许相机权限。" }
        }
    }

    func close() {
        guard isOpen else { return }
        let finishedSession = currentSession
        let savedPhotos = photoCount
        let selectedDirector = sessionDirector
        let starting = sessionStartTask
        sessionDirector = nil
        sessionStartTask = nil
        isOpen = false
        isReady = false
        isThinking = false
        activeJob?.cancel()
        activeJob = nil
        lastSample = nil
        currentPhoto = nil
        latestPhoto = nil
        generation = UUID()
        camera.stop()

        // 先等这次 start 完成，再提交 end，避免网络乱序把会话又打开。
        // 没有配置远程 AI 时默认无需联网，也不伪造视觉观察小结。
        if let selectedDirector {
            Task { [weak self] in
                await starting?.value
                do {
                    if let checkpoint = try await selectedDirector.finishSession(
                        finishedSession, photosSaved: savedPhotos
                    ), checkpoint.isFresh {
                        self?.lastCheckpoint = checkpoint
                        self?.onCheckpoint?(checkpoint)
                    }
                } catch {
                    // 照片已保存在本机；短期文字交接失败不影响拍照。
                }
            }
        }
    }

    func switchLens() {
        guard isReady, latestPhoto == nil else { return }
        lensVersion += 1
        activeJob?.cancel()
        activeJob = nil
        isThinking = false
        lastSample = nil
        tip = "换个镜头看看……"
        camera.flip()
    }

    func capture(manual: Bool = true) {
        guard isOpen, isReady, latestPhoto == nil else { return }
        tip = manual ? "好，这张收下了。" : "这幕我想留住。咔嚓。"
        camera.shoot()
    }

    func nextShot() {
        latestPhoto = nil
        currentPhoto = nil
        tip = "继续走走看看，我会挑喜欢的瞬间。"
    }

    func saveToAlbum() {
        guard let photo = currentPhoto else { return }
        Task {
            do { try await PhotoVault.saveToPhotos(photo); notice = "已经存进相册啦。" }
            catch { notice = error.localizedDescription }
        }
    }

    func updateConfig() {
        UserDefaults.standard.set(serverAddress, forKey: "demo.serverAddress")
        UserDefaults.standard.set(useRemoteAI, forKey: "demo.useRemote")
    }

    private func addLine(_ text: String, role: CameraLine.Role) {
        let clean = String(text.prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lines.append(CameraLine(role: role, text: clean))
        if lines.count > 12 { lines.removeFirst(lines.count - 12) }
    }

    func sendChat() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isThinking else { return }
        draft = ""
        addLine(message, role: .user)
        let fresh = lastSample.flatMap { Date().timeIntervalSince($0.at) <= 16 ? $0 : nil }
        analyze(image: fresh?.data, signature: fresh?.signature, message: message)
    }

    private func observe(_ jpeg: Data, signature: [UInt8]) {
        guard autoShutter, isOpen, isReady, latestPhoto == nil, !isThinking else { return }
        analyze(image: jpeg, signature: signature, message: nil)
    }

    private func director() throws -> any CameraDirector {
        if !useRemoteAI { return LocalDemoDirector() }
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else {
            throw HTTPDirector.ClientError.invalidEndpoint
        }
        return HTTPDirector(endpoint: url, accessToken: sessionToken)
    }

    private func analyze(image: Data?, signature: [UInt8]?, message: String?) {
        guard isOpen, !isThinking else { return }
        isThinking = true
        let epoch = generation, lens = lensVersion
        let snapshot = lines, alreadySaved = photoCount > 0, session = currentSession
        activeJob = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == epoch { self.isThinking = false; self.activeJob = nil }
            }
            do {
                let selected: any CameraDirector
                if let configured = self.sessionDirector { selected = configured }
                else { selected = try self.director() }
                let decision = try await selected.respond(
                    imageJPEG: image, message: message, recent: snapshot,
                    hasPhoto: alreadySaved, sessionID: session)
                guard !Task.isCancelled, self.isOpen, self.generation == epoch,
                      self.lensVersion == lens else { return }
                self.tip = decision.say
                self.addLine(decision.say, role: .companion)
                if decision.action == .CAPTURE, self.autoShutter,
                   self.latestPhoto == nil, let signature,
                   self.camera.sceneStillSimilar(to: signature) {
                    self.capture(manual: false)
                }
            } catch {
                guard self.isOpen, self.generation == epoch else { return }
                self.notice = error.localizedDescription
            }
        }
    }

    private func photoDidFinish(_ bytes: Data?) {
        guard isOpen else { return }
        guard let bytes, let image = UIImage(data: bytes) else {
            notice = "相机没有拿到照片，可以再拍一次。"
            return
        }
        do {
            // 原片先入沙盒；后续聊天压缩失败也不会抹掉照片。
            let original = try PhotoVault.saveOriginal(bytes)
            currentPhoto = original
            latestPhoto = image
            photoCount += 1
            tip = "拍到啦！这张我先替你收好了。"
        } catch { notice = "照片拍到了，但保存本机文件失败：\(error.localizedDescription)" }
    }
}
