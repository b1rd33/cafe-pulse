import Accelerate
import Foundation

struct FFTBandPower: Sendable {
    var subBass: Double = 0
    var bass: Double = 0
    var lowMid: Double = 0
    var mid: Double = 0
    var upperMid: Double = 0
    var presence: Double = 0
    var brilliance: Double = 0

    /// Spectral flatness in the voice band (300Hz-4kHz).
    /// 0.0 = pure tone (single speaker or silence), 1.0 = noise-like (crowd babble).
    var voiceBandSpectralFlatness: Double = 0

    mutating func add(power: Double, for frequency: Double) {
        switch frequency {
        case 20..<60:
            subBass += power
        case 60..<250:
            bass += power
        case 250..<500:
            lowMid += power
        case 500..<2_000:
            mid += power
        case 2_000..<4_000:
            upperMid += power
        case 4_000..<6_000:
            presence += power
        case 6_000...:
            brilliance += power
        default:
            break
        }
    }

    mutating func add(_ other: FFTBandPower) {
        subBass += other.subBass
        bass += other.bass
        lowMid += other.lowMid
        mid += other.mid
        upperMid += other.upperMid
        presence += other.presence
        brilliance += other.brilliance
        // spectralFlatness is per-window, averaged separately
    }

    func scaled(by scale: Double) -> FFTBandPower {
        FFTBandPower(
            subBass: subBass * scale,
            bass: bass * scale,
            lowMid: lowMid * scale,
            mid: mid * scale,
            upperMid: upperMid * scale,
            presence: presence * scale,
            brilliance: brilliance * scale,
            voiceBandSpectralFlatness: voiceBandSpectralFlatness
        )
    }

    /// Sub-bass + bass — reliable proxy for "how loud is the sound system."
    /// Crowd voices don't produce energy below 250Hz.
    var musicProxyPower: Double {
        subBass + bass
    }

    /// Mid + upper-mid — all human voice energy (yours + crowd + music vocals).
    var voiceProxyPower: Double {
        mid + upperMid
    }
}

final class FFTBandAnalyzer {
    let fftSize: Int

    private let window: [Float]
    private let zeroImaginary: [Float]
    private let transform: vDSP.DiscreteFourierTransform<Float>

    init(fftSize: Int = 4_096) throws {
        precondition(fftSize > 0, "FFT size must be positive.")

        self.fftSize = fftSize
        self.window = (0..<fftSize).map { index in
            let numerator = 2 * Double.pi * Double(index)
            let denominator = Double(max(fftSize - 1, 1))
            return Float(0.5 - 0.5 * cos(numerator / denominator))
        }
        self.zeroImaginary = [Float](repeating: 0, count: fftSize)
        self.transform = try vDSP.DiscreteFourierTransform(
            count: fftSize,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        )
    }

    func analyze(samples: ArraySlice<Float>, sampleRate: Double) -> FFTBandPower {
        guard sampleRate > 0 else {
            return FFTBandPower()
        }

        var realInput = [Float](repeating: 0, count: fftSize)
        for (index, sample) in samples.prefix(fftSize).enumerated() {
            realInput[index] = sample * window[index]
        }

        let output = transform.transform(real: realInput, imaginary: zeroImaginary)

        var bandPower = FFTBandPower()
        let halfBinCount = fftSize / 2
        let normalization = Double(fftSize)

        // Collect voice-band bin magnitudes for spectral flatness calculation
        var voiceBinPowers: [Double] = []

        for bin in 1..<halfBinCount {
            let frequency = Double(bin) * sampleRate / Double(fftSize)
            let power = Double(output.real[bin] * output.real[bin] + output.imaginary[bin] * output.imaginary[bin]) / normalization
            bandPower.add(power: power, for: frequency)

            // Voice band: 300Hz - 4kHz
            if frequency >= 300 && frequency < 4_000 {
                voiceBinPowers.append(power)
            }
        }

        // Spectral flatness = geometric mean / arithmetic mean of voice band bins.
        // Ranges from 0 (pure tone) to 1 (white noise / crowd babble).
        bandPower.voiceBandSpectralFlatness = computeSpectralFlatness(voiceBinPowers)

        return bandPower
    }

    /// Spectral flatness: geometric_mean / arithmetic_mean.
    /// Uses log-domain for numerical stability.
    private func computeSpectralFlatness(_ powers: [Double]) -> Double {
        guard !powers.isEmpty else { return 0 }

        let epsilon = 1e-20
        var logSum: Double = 0
        var linearSum: Double = 0

        for p in powers {
            let clamped = max(p, epsilon)
            logSum += log(clamped)
            linearSum += clamped
        }

        let n = Double(powers.count)
        let geometricMean = exp(logSum / n)
        let arithmeticMean = linearSum / n

        guard arithmeticMean > epsilon else { return 0 }
        return min(geometricMean / arithmeticMean, 1.0)
    }
}
