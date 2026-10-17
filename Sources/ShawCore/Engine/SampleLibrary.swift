import AVFoundation
import Foundation

/// Decoded audio files plus waveform overviews for drawing.
///
/// Everything it hands out stays cached for the life of the app, so the audio thread can hold
/// references to it without ever being the one that frees the memory.
public final class SampleLibrary {
    public static let shared = SampleLibrary()

    private var data: [String: SampleData] = [:]
    private var peaks: [String: [Float]] = [:]
    private var loading: Set<String> = []
    /// Sampler files, with their half-rate copies (built off the main thread).
    private var mips: [String: MipSample] = [:]
    private var mipLoading: Set<String> = []
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

    /// The file ready for the sampler, or nil while it loads (`onLoad` fires when it's ready).
    public func mipmapped(for path: String) -> MipSample? {
        lock.lock()
        if let m = mips[path] { lock.unlock(); return m }
        let start = !mipLoading.contains(path)
        // Decoding here too: mark it, so asking for its data or waveform meanwhile doesn't decode it twice.
        let decodes = start && data[path] == nil && !loading.contains(path)
        if start { mipLoading.insert(path) }
        if decodes { loading.insert(path) }
        lock.unlock()
        if start { DispatchQueue.global(qos: .userInitiated).async { self.buildMips(path, decodes: decodes) } }
        return nil
    }

    private func load(_ path: String) {
        let decoded = try? SampleLibrary.decode(URL(fileURLWithPath: path))
        lock.lock()
        loading.remove(path)
        if let d = decoded, data[path] == nil {
            data[path] = d
            peaks[path] = SampleLibrary.computePeaks(d)
        }
        lock.unlock()
        if decoded != nil {
            DispatchQueue.main.async { self.onLoad?(path) }
        }
    }

    private func buildMips(_ path: String, decodes: Bool) {
        lock.lock()
        var base = data[path]
        lock.unlock()
        if base == nil {
            if !decodes {
                // Someone else is decoding it already: wait for that rather than doing it twice.
                for _ in 0..<1500 {
                    Thread.sleep(forTimeInterval: 0.02)
                    lock.lock()
                    base = data[path]
                    let busy = loading.contains(path)
                    lock.unlock()
                    if base != nil || !busy { break }
                }
            }
            if base == nil, let d = try? SampleLibrary.decode(URL(fileURLWithPath: path)) {
                lock.lock()
                if let existing = data[path] { base = existing } else {
                    data[path] = d
                    peaks[path] = SampleLibrary.computePeaks(d)
                    base = d
                }
                lock.unlock()
            }
            if decodes {
                lock.lock()
                loading.remove(path)
                lock.unlock()
            }
        }
        let m = base.map { MipSample($0) }
        lock.lock()
        mipLoading.remove(path)
        if let m { mips[path] = m }
        lock.unlock()
        if m != nil {
            DispatchQueue.main.async { self.onLoad?(path) }
        }
    }

    /// A file for a quick listen (the Samples browser): at most `maxSeconds`, and not kept in the
    /// cache unless something already loaded it. Calls back on the main queue.
    public func loadForPreview(_ path: String, maxSeconds: Double = 30, completion: @escaping (MipSample?) -> Void) {
        lock.lock()
        let cached = data[path]
        lock.unlock()
        if let cached {
            completion(MipSample(cached, maxLevels: 0))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let d = try? SampleLibrary.decode(URL(fileURLWithPath: path), maxSeconds: maxSeconds)
            let m = d.map { MipSample($0, maxLevels: 0) }
            DispatchQueue.main.async { completion(m) }
        }
    }

    public static func decode(_ url: URL, maxSeconds: Double? = nil) throws -> SampleData {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        var count = AVAudioFrameCount(file.length)
        if let maxSeconds { count = min(count, AVAudioFrameCount(max(1, maxSeconds * fmt.sampleRate))) }
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: max(count, 1)) else {
            throw NSError(domain: "Shaw", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not allocate buffer"])
        }
        try file.read(into: buf, frameCount: max(count, 1))
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

    /// File types the Samples browser lists (anything AVFoundation can usually open).
    public static let audioExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "aifc", "caf", "mp3", "m4a", "aac", "flac", "mp4"]

    public static func isAudioFile(_ url: URL) -> Bool { audioExtensions.contains(url.pathExtension.lowercased()) }
}
