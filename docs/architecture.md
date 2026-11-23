# 设计说明：让模型真正按下快门

这套实现刻意分成三个小东西，便于单独替换。

## 1. 相机：AVFoundation

`CameraHardware.swift` 负责后置与前置摄像头、实时预览、照片捕获。它不需要麦克风，也不依赖 WebView。真实的拍照发生在：

```swift
stillOutput.capturePhoto(with: options, delegate: self)
```

`CameraStudioModel.swift` 只负责组织状态：打开/关闭相机、处理模型回复、核对当前构图、保存原片。SwiftUI 用 `CameraStudioView.swift` 观察状态。

## 2. 低频观察：FrameGate

无需每帧都上传给大模型。`CameraFrameGate.swift` 对实时画面每约 0.4 秒抽取一个 24×24 灰度签名，在本机判断画面是否稳定、是否明显变化。

当出现值得重新看的新构图时，才把一帧压缩到最长边约 512 px、JPEG 约 110 KB 的范围，交给视觉服务。固定画面会延后重复送图。这既节约费用，也减少了无意义的等待。

当视觉模型经过若干秒返回 `CAPTURE`，客户端还会检查**当前镜头是不是仍然朝着同一个大致场景**。大幅换景时放弃这次指令；轻微手持晃动则不必要求摄影棚般的稳定。

## 3. AI：一个极小的可替换接口

```json
{
  "sessionId": "你的 UUID",
  "imageBase64": "一张 JPEG 的 base64（可省略）",
  "message": "你对 AI 说的话（可省略）",
  "hasPhoto": false,
  "recent": [
    { "role": "user", "text": "你喜欢这只小玩偶吗？" },
    { "role": "companion", "text": "它笑得很可爱。" }
  ]
}
```

回复：

```json
{ "action": "CAPTURE", "say": "它歪着头的这张，我想拍。" }
```

- `WAIT`：不拍，但可以自然聊天。
- `CAPTURE`：原生 App 检查当下镜头后，调用真实快门。
- 如果这次没有图片，只是文字聊天，则后端不会发出可执行的自动快门指令。

`App/CameraDirector.swift` 中的协议可以替换成任意视觉模型。`backend/server.mjs` 是一个使用 OpenAI Responses API 和结构化 JSON 回复的参考实现，**无需公开或提交模型密钥**。

后端默认绑定本机 `127.0.0.1`，外部 iPhone 需要你配置自己的 HTTPS 入口。不要直接把模型 API Key 放在手机 App 源代码里。

## 想把它做成更像你的 AI 伴侣

这条路线已经包含在仓库里，而不只是建议：

- `backend/context.mjs` 为每次拍摄建立独立的、12 分钟过期的有界文字会话。画面每五帧折叠一轮旧观察，每次视觉 API 调用都无状态，**没有累积图片历史的长线程**。
- `App/CameraDirector.swift` 增加了 `beginSession` / `finishSession`；`CameraStudioModel` 会在开启和关闭相机时调用。
- `App/CameraContext.swift` 提供 `CameraContextInbox`，让你自己的主聊天**读一次、成功后再确认消费**。只有文字和手机实际保存的照片数，没有原始图像。

完整代码、三条 HTTP 接口、SwiftUI 集成示例和上限见 [《相机的小纸条：短期上下文》](context-bridge.md)。

不需要把每张画面塞进主线程，也不必让相机一直占用后台任务。AI 只记下刚刚一起看过什么，就已经很像陪伴了。
