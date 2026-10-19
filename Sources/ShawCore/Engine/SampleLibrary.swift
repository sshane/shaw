import AVFoundation
import Foundation

/// A recorded instrument: a folder of notes recorded a few semitones apart, each file named by its
/// MIDI note ("060.caf"). Every note plays the recording nearest to it, pitched the rest of the way.
public final class SampleZones {
    /// Recorded notes, lowest first, and their recordings.
    public let roots: [Int]
    let samples: [MipSample]

    public init(_ zones: [(root: Int, sample: MipSample)]) {
        let sorted = zones.sorted { $0.root < $1.root }
        roots = sorted.map(\.root)
        samples = sorted.map(\.sample)
    }

    /// The recording nearest to `note` and the note it was recorded at. Halfway between two, it
    /// takes the higher one: pitching a recording down sounds more natural than pitching it up.
    /// Audio thread safe.
    @inline(__always) func zone(for note: Int) -> (MipSample, Int) {
        var best = 0
        for i in roots.indices where abs(roots[i] - note) <= abs(roots[best] - note) { best = i }
        return (samples[best], roots[best])
    }
}

/// What a sampler plays: one file pitched across the keyboard, or a recorded instrument.
public enum SamplerSource {
    case file(MipSample)
    case zones(SampleZones)

    /// The recording for a note and the note it was recorded at (nil: the Root Note control decides).
    @inline(__always) func pick(_ note: Int) -> (MipSample, Int?) {
        switch self {
        case .file(let m): return (m, nil)
        case .zones(let z): let (m, root) = z.zone(for: note); return (m, root)
        }
    }
}

/// Decoded audio files plus waveform overviews for drawing.
///
/// Everything it hands out stays cached for the life of the app, so the audio thread can hold
/// references to it without ever being the one that frees the memory.
public final class SampleLibrary {
    public static let shared = SampleLibrary()

    // MARK: Sounds that come with Shaw

    /// Paths of the sounds that come with Shaw start with this ("shaw:Instruments/Grand Piano"),
    /// so projects keep finding them wherever the app is.
    public static let bundledPrefix = "shaw:"

    /// The app's Resources/Sounds, or the repository's when running from the source tree (tests).
    public static let bundledRoot: URL = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Sounds"), FileManager.default.fileExists(atPath: r.path) { return r }
        // Sources/ShawCore/Engine/SampleLibrary.swift → the repository.
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { u.deleteLastPathComponent() }
        return u.appendingPathComponent("Resources/Sounds")
    }()

    public static func isBundled(_ path: String) -> Bool { path.hasPrefix(bundledPrefix) }

    /// Where a path is on disk. Sounds that come with Shaw resolve inside the app.
    public static func fileURL(_ path: String) -> URL {
        guard isBundled(path) else { return URL(fileURLWithPath: path) }
        return bundledRoot.appendingPathComponent(String(path.dropFirst(bundledPrefix.count)))
    }

    /// A file inside the app's own sounds, written the portable way ("shaw:Percussion/Shaker.caf").
    /// Anything else comes back unchanged.
    public static func portablePath(_ path: String) -> String {
        let root = bundledRoot.standardizedFileURL.path + "/"
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return p.hasPrefix(root) ? bundledPrefix + p.dropFirst(root.count) : path
    }

    public static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: fileURL(path).path) }

    private var data: [String: SampleData] = [:]
    private var peaks: [String: [Float]] = [:]
    private var loading: Set<String> = []
    /// Sampler files, with their half-rate copies (built off the main thread).
    private var mips: [String: MipSample] = [:]
    private var mipLoading: Set<String> = []
    /// Recorded instruments (folders of notes), and which sampler paths are folders.
    private var zoneSets: [String: SampleZones] = [:]
    private var zoneLoading: Set<String> = []
    private var folders: [String: Bool] = [:]
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

    /// True when a sampler path is a recorded instrument (a folder of notes) rather than one file.
    public func isFolder(_ path: String) -> Bool {
        lock.lock()
        if let f = folders[path] { lock.unlock(); return f }
        lock.unlock()
        var dir: ObjCBool = false
        let f = FileManager.default.fileExists(atPath: SampleLibrary.fileURL(path).path, isDirectory: &dir) && dir.boolValue
        lock.lock()
        folders[path] = f
        lock.unlock()
        return f
    }

    /// What a sampler path plays, ready for the audio thread, or nil while it loads (`onLoad` fires
    /// when it's ready).
    public func samplerSource(for path: String) -> SamplerSource? {
        guard isFolder(path) else { return mipmapped(for: path).map { .file($0) } }
        lock.lock()
        if let z = zoneSets[path] { lock.unlock(); return .zones(z) }
        let start = !zoneLoading.contains(path)
        if start { zoneLoading.insert(path) }
        lock.unlock()
        if start { DispatchQueue.global(qos: .userInitiated).async { self.buildZones(path) } }
        return nil
    }

    private func buildZones(_ path: String) {
        let z = SampleLibrary.loadZones(SampleLibrary.fileURL(path))
        lock.lock()
        zoneLoading.remove(path)
        if let z { zoneSets[path] = z }
        lock.unlock()
        if z != nil { DispatchQueue.main.async { self.onLoad?(path) } }
    }

    /// Decode every note in a recorded instrument's folder, several at a time.
    static func loadZones(_ folder: URL) -> SampleZones? {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter(isAudioFile)
        var out = [(root: Int, sample: MipSample)?](repeating: nil, count: files.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: files.count) { i in
            let url = files[i]
            guard let note = Int(url.deletingPathExtension().lastPathComponent.prefix { $0.isNumber }), (0...127).contains(note),
                  let d = try? decode(url) else { return }
            let m = MipSample(d)
            lock.lock()
            out[i] = (note, m)
            lock.unlock()
        }
        let zones = out.compactMap { $0 }
        return zones.isEmpty ? nil : SampleZones(zones)
    }

    private func load(_ path: String) {
        let decoded = try? SampleLibrary.decode(SampleLibrary.fileURL(path))
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
            if base == nil, let d = try? SampleLibrary.decode(SampleLibrary.fileURL(path)) {
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
            let d = try? SampleLibrary.decode(SampleLibrary.fileURL(path), maxSeconds: maxSeconds)
            let m = d.map { MipSample($0, maxLevels: 0) }
            DispatchQueue.main.async { completion(m) }
        }
    }

    /// Decode a file converted to another sample rate (the recorded drum kit, so it matches the engine).
    public static func decode(_ url: URL, sampleRate target: Double) throws -> SampleData {
        let d = try decode(url)
        guard abs(d.sampleRate - target) > 0.5 else { return d }
        let ch = AVAudioChannelCount(d.channels)
        guard let inFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: d.sampleRate, channels: ch, interleaved: false),
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: target, channels: ch, interleaved: false),
              let conv = AVAudioConverter(from: inFmt, to: outFmt),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(d.frames)) else { return d }
        inBuf.frameLength = AVAudioFrameCount(d.frames)
        inBuf.floatChannelData![0].update(from: d.l, count: d.frames)
        if ch > 1 { inBuf.floatChannelData![1].update(from: d.r, count: d.frames) }
        conv.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        let cap = AVAudioFrameCount(Double(d.frames) * target / d.sampleRate) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return d }
        var given = false
        var err: NSError?
        _ = conv.convert(to: outBuf, error: &err) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true
            status.pointee = .haveData
            return inBuf
        }
        let n = Int(outBuf.frameLength)
        guard err == nil, n > 0 else { return d }
        let l = Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: n))
        let r = ch > 1 ? Array(UnsafeBufferPointer(start: outBuf.floatChannelData![1], count: n)) : nil
        return SampleData(left: l, right: r, sampleRate: target)
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
