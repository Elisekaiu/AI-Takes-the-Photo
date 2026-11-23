# 一边打电话，一边让 AI 拍照

如果你已经有能接听电话的 AI 伴侣，最简单的做法不是再建一套通话：**只在正在运行的电话页面上，加一层 SwiftUI Camera Studio。**

## 一个简单思路

```swift
ZStack {
    ExistingCallView() // 原来的 WebRTC / CallKit / STT / TTS 不要销毁

    if showCamera {
        CameraStudioView() // 只管理视频，不新建麦克风
    }
}
```

页面上放一个「一起拍」按钮，将 `showCamera = true`。关闭拍照小窗时恢复原来的通话页。

本项目相机没有 `AVCaptureAudioDataOutput`，并设置：

```swift
session.automaticallyConfiguresApplicationAudioSession = false
```

这样可以避免相机**主动**把已有的音频设置改成录视频的路由。实际是否与 WebRTC、网页麦克风、蓝牙耳机稳定共存，仍与对方的音频 SDK 和 iOS 版本有关；请在自己的真实通话上试一下。

## 电话里的 AI 如何知道看到了什么？

建议给相机一个独立的视觉线程。它按较低频率读取 JPEG 取样，返回一句文字描述或拍摄决定。电话的主线程在下一次语音回合里，只需要得到一个非常短的摘要：

> 「相机大约 8 秒前看过一只圆滚滚的玩偶，视觉伙伴说它歪着头很可爱。」

请同时传递观察的时间，不要把过时画面描述成此刻正在看到的景象。

仓库现在提供一个可以直接使用的通用接续接口：相机结束后由 `onCheckpoint` 回调把小结交给 [`CameraContextInbox`](../App/CameraContext.swift)，电话下一次语音回合可取出文字，**回复成功后再 acknowledge**。完整用法在 [短期上下文说明](context-bridge.md)。

原始画面走相机线程，音频走原本通话线程；两边交汇的是**少量文字**，而不是成百张帧截图。

## Demo 和真正的电话

仓库首页的「演示通话中的相机入口」仅用于体验布局，不会向任何号码拨电话。`Examples/CallIntegration.swift` 是嵌入写法示例。你已有的通话 App 接这层 SwiftUI 时，不需要照搬我们的私人电话后端。
