import Foundation

@main
struct RunFrameGateTests {
    static func main() {
        let a = [UInt8](repeating: 100, count: 24*24)
        let b = [UInt8](repeating: 200, count: 24*24)
        precondition(CameraFrameGate.difference(a, a) == 0)
        precondition(CameraFrameGate.difference(a, b) > 0.2)
        var gate = CameraFrameGate()
        precondition(!gate.shouldSample(a, at: 0))
        precondition(!gate.shouldSample(a, at: 0.4))
        precondition(gate.shouldSample(a, at: 1.5))
        gate.didSend(at: 1.5)
        precondition(!gate.shouldSample(a, at: 12))
        precondition(gate.shouldSample(a, at: 24))
        gate.didSend(at: 24)
        precondition(!gate.shouldSample(b, at: 25))
        precondition(!gate.shouldSample(b, at: 25.5))
        precondition(gate.shouldSample(b, at: 33))
        gate.reset()
        precondition(!gate.shouldSample(a, at: 34))
        print("CameraFrameGate: 全部通过")
    }
}
