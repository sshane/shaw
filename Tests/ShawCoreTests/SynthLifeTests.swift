import XCTest
@testable import ShawCore

/// Stereo width and velocity brightness: what keeps the synth from sounding small and static next to
/// the recorded instruments.
final class SynthLifeTests: XCTestCase {
    let sr = 48000.0
    typealias A = AudioAnalysis

    /// Keys without drift or drive, so two renders differ only in what's being tested.
    func keys(_ extra: [String: Double]) -> [String: Double] {
        SynthPresets.params(for: "Keys").merging(["drift": 0, "drive": 0]) { $1 }.merging(extra) { $1 }
    }

    func correlation(_ l: [Float], _ r: [Float]) -> Double {
        var lr = 0.0, ll = 0.0, rr = 0.0
        for i in Int(0.05 * sr)..<l.count { lr += Double(l[i] * r[i]); ll += Double(l[i] * l[i]); rr += Double(r[i] * r[i]) }
        return lr / max(1e-12, sqrt(ll * rr))
    }

    func testWidthSpreadsTheSoundButSumsToTheSameNote() {
        let wide = Synth.renderNote(keys(["width": 0.6]), note: 64, hold: 1)
        let mono = Synth.renderNote(keys(["width": 0]), note: 64, hold: 1)
        XCTAssertEqual(correlation(mono.l, mono.r), 1, accuracy: 1e-6)
        XCTAssertLessThan(correlation(wide.l, wide.r), 0.8, "the sides differ, like a recording")
        XCTAssertGreaterThan(correlation(wide.l, wide.r), 0.3, "but it's still one instrument in the middle")
        let mid = zip(wide.l, wide.r).map { ($0 + $1) * 0.5 }
        let diff = zip(mid, mono.l).map { $0 - $1 }
        XCTAssertLessThan(A.rms(diff), A.rms(mono.l) * 0.02, "summed to mono it's the plain note: nothing cancels on a phone speaker")
    }

    func testLowNotesStayInTheMiddle() {
        let bass = Synth.renderNote(keys(["width": 1]), note: 33, hold: 1) // A1, 55 Hz
        XCTAssertEqual(correlation(bass.l, bass.r), 1, accuracy: 1e-6, "basses keep a solid mono low end")
    }

    func testHarderNotesAreBrighter() {
        func centroid(_ v: Float, _ params: [String: Double]) -> Double {
            let x = Synth.renderNote(params, note: 60, velocity: v, hold: 0.3).l
            let spec = A.powerSpectrum(x, start: Int(0.02 * sr), length: 8192)
            let hz = A.binHz(spec, sr)
            var num = 0.0, den = 0.0
            for (i, p) in spec.enumerated() { num += Double(i) * hz * p; den += p }
            return num / den
        }
        let p = keys([:])
        XCTAssertGreaterThan(centroid(1, p), centroid(0.35, p) * 1.15, "a hard note is clearly brighter than a soft one")
        XCTAssertEqual(centroid(0.8, p), centroid(0.8, keys(["velcut": 0])), accuracy: 1, "notes at the usual velocity don't change")
    }
}
