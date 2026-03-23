import XCTest
@testable import CafePulse

final class FFTBandAnalyzerTests: XCTestCase {
    var analyzer: FFTBandAnalyzer!
    let sampleRate: Double = 44100

    override func setUpWithError() throws {
        analyzer = try FFTBandAnalyzer(fftSize: 4096)
    }

    // Test 1: Silence → all bands near zero power
    func testSilenceProducesNearZeroPower() {
        let silence = [Float](repeating: 0, count: 4096)
        let result = analyzer.analyze(samples: silence[...], sampleRate: sampleRate)
        XCTAssertEqual(result.musicProxyPower, 0, accuracy: 1e-10)
        XCTAssertEqual(result.voiceProxyPower, 0, accuracy: 1e-10)
    }

    // Test 2: 100Hz sine wave → bass band has energy, voice band has much less
    func testBassSineWaveDetectedInMusicBand() {
        let frequency: Float = 100
        let samples = (0..<4096).map { i in
            sinf(2 * .pi * frequency * Float(i) / Float(sampleRate))
        }
        let result = analyzer.analyze(samples: samples[...], sampleRate: sampleRate)
        XCTAssertGreaterThan(result.musicProxyPower, result.voiceProxyPower * 10,
            "100Hz tone should have >10x more energy in music band than voice band")
    }

    // Test 3: 1kHz sine wave → voice band has energy, bass band has much less
    func testMidSineWaveDetectedInVoiceBand() {
        let frequency: Float = 1000
        let samples = (0..<4096).map { i in
            sinf(2 * .pi * frequency * Float(i) / Float(sampleRate))
        }
        let result = analyzer.analyze(samples: samples[...], sampleRate: sampleRate)
        XCTAssertGreaterThan(result.voiceProxyPower, result.musicProxyPower * 10,
            "1kHz tone should have >10x more energy in voice band than music band")
    }

    // Test 4: Spectral flatness of pure tone → near 0
    func testSpectralFlatnessPureToneIsLow() {
        let frequency: Float = 1000
        let samples = (0..<4096).map { i in
            sinf(2 * .pi * frequency * Float(i) / Float(sampleRate))
        }
        let result = analyzer.analyze(samples: samples[...], sampleRate: sampleRate)
        XCTAssertLessThan(result.voiceBandSpectralFlatness, 0.1,
            "Pure tone should have spectral flatness near 0")
    }

    // Test 5: White noise → spectral flatness closer to 1
    func testSpectralFlatnessWhiteNoiseIsHigh() {
        var samples = [Float](repeating: 0, count: 4096)
        for i in 0..<4096 {
            samples[i] = Float.random(in: -1...1)
        }
        let result = analyzer.analyze(samples: samples[...], sampleRate: sampleRate)
        XCTAssertGreaterThan(result.voiceBandSpectralFlatness, 0.5,
            "White noise should have spectral flatness > 0.5")
    }

    // Test 6: FFTBandPower computed properties
    func testBandPowerComputedProperties() {
        var power = FFTBandPower()
        power.subBass = 1.0
        power.bass = 2.0
        power.mid = 3.0
        power.upperMid = 4.0
        XCTAssertEqual(power.musicProxyPower, 3.0)  // subBass + bass
        XCTAssertEqual(power.voiceProxyPower, 7.0)   // mid + upperMid
    }

    // Test 7: Empty samples returns default power
    func testEmptySamplesReturnsDefaultPower() {
        let result = analyzer.analyze(samples: [][...], sampleRate: sampleRate)
        XCTAssertEqual(result.musicProxyPower, 0)
        XCTAssertEqual(result.voiceProxyPower, 0)
    }

    // Test 8: Zero sample rate returns default
    func testZeroSampleRateReturnsDefault() {
        let samples = [Float](repeating: 0.5, count: 4096)
        let result = analyzer.analyze(samples: samples[...], sampleRate: 0)
        XCTAssertEqual(result.musicProxyPower, 0)
    }
}
