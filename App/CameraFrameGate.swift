import Foundation

/// 24×24 亮度签名：一切判断都在本机完成，不需要上传整段视频。
struct CameraFrameGate {
    static let side = 24
    private let stableDifference = 0.085
    private let sceneDifference = 0.07
    private let holdSeconds = 0.75
    private let newSceneGap = 7.0
    private let unchangedGap = 22.0

    private var previous: [UInt8]?
    private var stableFrom: TimeInterval?
    private var lastSent: [UInt8]?
    private var lastSentAt = -Double.infinity
    private var lastObserved: [UInt8]?
    private var lastObservedAt = -Double.infinity

    mutating func reset() {
        previous = nil
        stableFrom = nil
        lastSent = nil
        lastSentAt = -.infinity
        lastObserved = nil
        lastObservedAt = -.infinity
    }

    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 1 }
        let sum = zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(sum) / (Double(a.count) * 255.0)
    }

    mutating func shouldSample(_ pixels: [UInt8], at now: TimeInterval) -> Bool {
        guard pixels.count == Self.side * Self.side, now > lastObservedAt else { return false }
        if let previous {
            if Self.difference(previous, pixels) <= stableDifference {
                if stableFrom == nil { stableFrom = now }
            } else {
                stableFrom = nil
            }
        }
        previous = pixels
        lastObserved = pixels
        lastObservedAt = now
        guard let stableFrom, now - stableFrom >= holdSeconds else { return false }
        guard now - lastSentAt >= newSceneGap else { return false }
        let changed = lastSent.map { Self.difference($0, pixels) >= sceneDifference } ?? true
        return changed || now - lastSentAt >= unchangedGap
    }

    mutating func didSend(at now: TimeInterval) {
        guard now == lastObservedAt, let lastObserved else { return }
        lastSent = lastObserved
        lastSentAt = now
    }
}
