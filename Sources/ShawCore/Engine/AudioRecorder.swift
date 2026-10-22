import AVFoundation
import CoreAudio
import Foundation

/// Records the microphone (or any input) to a file. It runs its own input-only audio engine, so the
/// input and the output can be different devices (a USB mic and AirPods, say). While it records it
/// keeps a running waveform and level for the screen, and the host time of its first sample, which
/// the app lines up with the song's clock to place the take exactly where it was sung.
public final class AudioRecorder {
    public enum Permission { case granted, denied, undetermined }

    public enum RecorderError: LocalizedError {
        case noInput
        public var errorDescription: String? { "No microphone or audio input was found." }
    }

    /// What a finished recording is: its file, length, rate, and when its first sample was captured.
    public struct Take {
        public var url: URL
        public var frames: Int
        public var sampleRate: Double
        /// Host time (in nanoseconds) the first recorded sample arrived, or nil if the device didn't say.
        public var firstSampleNanos: UInt64?
        public var duration: Double { Double(frames) / sampleRate }
    }

    public static var permission: Permission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    /// Asks once; macOS shows its own prompt the first time, then remembers the answer.
    public static func requestPermission(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { done(ok) } }
    }

    /// One waveform point (the peak) for every this many seconds of recording.
    public static let peakInterval = 0.01

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var url: URL?
    private let lock = NSLock()
    private var peaks: [Float] = []
    private var pendingPeak: Float = 0, pendingFrames = 0
    private var level: Float = 0
    private var frames = 0
    private var firstNanos: UInt64?
    public private(set) var sampleRate = 48000.0
    public var isRunning: Bool { engine != nil }

    public init() {}

    /// Start listening to the default input. With a `url`, everything is also written there (mono,
    /// 24-bit, at the input's own rate); without one, it only meters the level.
    public func start(writingTo url: URL?) throws {
        stop()
        let e = AVAudioEngine()
        let input = e.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0,
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: fmt.sampleRate, channels: 1, interleaved: false)
        else { throw RecorderError.noInput }
        sampleRate = fmt.sampleRate
        lock.lock()
        peaks = []; pendingPeak = 0; pendingFrames = 0; level = 0; frames = 0; firstNanos = nil
        lock.unlock()
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: fmt.sampleRate, AVNumberOfChannelsKey: 1,
                                           AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                                           AVLinearPCMIsNonInterleaved: false]
            file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            self.url = url
        }
        // The tap runs on its own thread, not the real-time one, so writing the file here is fine.
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, when in
            self?.receive(buf, when: when, mono: mono)
        }
        try e.start()
        engine = e
    }

    /// Stop, close the file, and say what was recorded (nil if it was only metering).
    @discardableResult
    public func stop() -> Take? {
        guard let e = engine else { return nil }
        e.inputNode.removeTap(onBus: 0)
        e.stop()
        engine = nil
        file = nil // closing finishes the file
        defer { url = nil }
        guard let url else { return nil }
        lock.lock(); defer { lock.unlock() }
        return Take(url: url, frames: frames, sampleRate: sampleRate, firstSampleNanos: firstNanos)
    }

    /// The waveform so far (one peak per `peakInterval`) and the current input level (0...1).
    public func snapshot() -> (peaks: [Float], level: Float, seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        return (peaks, level, Double(frames) / sampleRate)
    }

    /// Feed audio in as if it came from the input (tests).
    func receiveForTesting(_ buf: AVAudioPCMBuffer, hostNanos: UInt64?) {
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: buf.format.sampleRate, channels: 1, interleaved: false)!
        sampleRate = buf.format.sampleRate
        let when = hostNanos.map { AVAudioTime(hostTime: AudioConvertNanosToHostTime($0)) } ?? AVAudioTime(sampleTime: 0, atRate: sampleRate)
        receive(buf, when: when, mono: mono)
    }

    private func receive(_ buf: AVAudioPCMBuffer, when: AVAudioTime, mono: AVAudioFormat) {
        let n = Int(buf.frameLength)
        guard n > 0, let src = buf.floatChannelData, let out = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(n)) else { return }
        out.frameLength = AVAudioFrameCount(n)
        // Mono: the average of the input's channels.
        let chans = Int(buf.format.channelCount)
        let dst = out.floatChannelData![0]
        for i in 0..<n {
            var s: Float = 0
            for c in 0..<chans { s += src[c][i] }
            dst[i] = s / Float(chans)
        }
        try? file?.write(from: out)
        let per = max(1, Int(sampleRate * Self.peakInterval))
        lock.lock()
        if firstNanos == nil, when.isHostTimeValid { firstNanos = AudioConvertHostTimeToNanos(when.hostTime) }
        var peak: Float = 0
        for i in 0..<n {
            let a = abs(dst[i])
            peak = max(peak, a)
            pendingPeak = max(pendingPeak, a)
            pendingFrames += 1
            if pendingFrames >= per { peaks.append(pendingPeak); pendingPeak = 0; pendingFrames = 0 }
        }
        level = max(peak, level * 0.8)
        frames += n
        lock.unlock()
    }

    // MARK: Latency

    /// How long sound takes from the mic to a recorded sample, in seconds (device + safety offset +
    /// stream latency + one buffer), for the default input device.
    public static func inputLatency() -> Double { latency(input: true) }

    /// How long a rendered sample takes to reach the speakers, for the default output device.
    public static func outputLatency() -> Double { latency(input: false) }

    private static func latency(input: Bool) -> Double {
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr, dev != 0 else { return 0 }
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        func frames(_ selector: AudioObjectPropertySelector, object: AudioObjectID = dev) -> UInt32 {
            var v = UInt32(0), s = UInt32(MemoryLayout<UInt32>.size)
            var a = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            return AudioObjectGetPropertyData(object, &a, 0, nil, &s, &v) == noErr ? v : 0
        }
        var total = frames(kAudioDevicePropertyLatency) + frames(kAudioDevicePropertySafetyOffset) + frames(kAudioDevicePropertyBufferFrameSize)
        // The first stream's own latency.
        var streamsAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var streamsSize = UInt32(0)
        if AudioObjectGetPropertyDataSize(dev, &streamsAddr, 0, nil, &streamsSize) == noErr, streamsSize >= UInt32(MemoryLayout<AudioStreamID>.size) {
            var streams = [AudioStreamID](repeating: 0, count: Int(streamsSize) / MemoryLayout<AudioStreamID>.size)
            if AudioObjectGetPropertyData(dev, &streamsAddr, 0, nil, &streamsSize, &streams) == noErr, let first = streams.first {
                total += frames(kAudioStreamPropertyLatency, object: first)
            }
        }
        var rate = Float64(0), rs = UInt32(MemoryLayout<Float64>.size)
        var rateAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(dev, &rateAddr, 0, nil, &rs, &rate) == noErr, rate > 0 else { return 0 }
        return Double(total) / rate
    }
}
