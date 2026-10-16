import AVFoundation
import Foundation

/// Decoded audio files plus waveform overviews for drawing.
public final class SampleLibrary {
    public static let shared = SampleLibrary()

    private var data: [String: SampleData] = [:]
    private var peaks: [String: [Float]] = [:]
    private var loading: Set<String> = []
    private let lock = NSLock()
    /// Frames per peak bucket in waveform overviews.
    public static let peakBucket = 256

    /// Called on the main queue after a file finishes loading.
    public var onLoad: ((String) -> Void)?

    public func data(for path: String) -> SampleData? {
        lock.lock(); defer { lock.unlock() }
        if let d = data[path] { return d }
        if !loading.contains(path) {
            loading.insert(path)
            DispatchQueue.global(qos: .userInitiated).async { self.load(path) }
        }
        return nil
    }

    public func peaks(for path: String) -> [Float]? {
        lock.lock(); defer { lock.unlock() }
        if peaks[path] == nil && data[path] == nil && !loading.contains(path) {
            loading.insert(path)
            DispatchQueue.global(qos: .userInitiated).async { self.load(path) }
        }
        return peaks[path]
    }

    public func sampleRate(for path: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        return data[path]?.sampleRate
    }

    private func load(_ path: String) {
        let decoded = try? SampleLibrary.decode(URL(fileURLWithPath: path))
        lock.lock()
        loading.remove(path)
        if let d = decoded {
            data[path] = d
            peaks[path] = SampleLibrary.computePeaks(d)
        }
        lock.unlock()
        if decoded != nil {
            DispatchQueue.main.async { self.onLoad?(path) }
        }
    }

    public static func decode(_ url: URL) throws -> SampleData {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        let count = AVAudioFrameCount(file.length)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: max(count, 1)) else {
            throw NSError(domain: "Shaw", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not allocate buffer"])
        }
        try file.read(into: buf)
        let n = Int(buf.frameLength)
        guard let ch = buf.floatChannelData else {
            throw NSError(domain: "Shaw", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"])
        }
        let l = Array(UnsafeBufferPointer(start: ch[0], count: n))
        let r = fmt.channelCount > 1 ? Array(UnsafeBufferPointer(start: ch[1], count: n)) : nil
        return SampleData(left: l, right: r, sampleRate: fmt.sampleRate)
    }

    /// Read basic info without decoding the whole file.
    public static func probe(_ url: URL) throws -> AudioFileRef {
        let file = try AVAudioFile(forReading: url)
        let sr = file.fileFormat.sampleRate
        return AudioFileRef(path: url.path, duration: Double(file.length) / sr, sampleRate: sr,
                            channels: Int(file.fileFormat.channelCount))
    }

    static func computePeaks(_ d: SampleData) -> [Float] {
        let b = peakBucket
        let count = (d.frames + b - 1) / b
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            var m: Float = 0
            let s = i * b, e = min(d.frames, s + b)
            for j in s..<e { m = max(m, abs(d.l[j]), abs(d.r[j])) }
            out[i] = m
        }
        return out
    }
}
