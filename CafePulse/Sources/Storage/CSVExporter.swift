import Foundation

struct CSVExporter {
    func export(snapshot: AppSnapshot, to destinationURL: URL) throws {
        let sessionsByID = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0) })
        let audioLookup = Dictionary(uniqueKeysWithValues: snapshot.audioSamples.map { (EventKey(sessionId: $0.sessionId, timestamp: $0.timestamp), $0) })
        let crowdLookup = Dictionary(uniqueKeysWithValues: snapshot.crowdEstimates.map { (EventKey(sessionId: $0.sessionId, timestamp: $0.timestamp), $0) })

        let sortedKeys = Set(audioLookup.keys).union(crowdLookup.keys).sorted {
            if $0.timestamp == $1.timestamp {
                return $0.sessionId.uuidString < $1.sessionId.uuidString
            }
            return $0.timestamp < $1.timestamp
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines = [header]

        for key in sortedKeys {
            let session = sessionsByID[key.sessionId]
            let audio = audioLookup[key]
            let crowd = crowdLookup[key]

            let row = [
                escape(key.sessionId.uuidString),
                escape(session?.cafeName ?? ""),
                escape(formatter.string(from: key.timestamp)),
                formatted(audio?.overallDB),
                formatted(audio?.musicBandDB),
                formatted(audio?.voiceBandDB),
                formatted(audio?.peakDB),
                formatted(audio?.spectralFlatness),
                audio?.selfTalkDetected == true ? "true" : (audio != nil ? "false" : ""),
                formatted(audio?.voiceBandVariance),
                escape(crowd?.fullness.rawValue ?? ""),
                crowd?.peopleCount.map(String.init) ?? ""
            ].joined(separator: ",")

            lines.append(row)
        }

        let output = lines.joined(separator: "\n")
        try output.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    private var header: String {
        "session_id,cafe_name,timestamp,overall_db,music_band_db,voice_band_db,peak_db,spectral_flatness,self_talk_detected,voice_band_variance,crowd_fullness,people_count"
    }

    private func formatted(_ value: Float?) -> String {
        guard let value else {
            return ""
        }

        return String(format: "%.2f", value)
    }

    private func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }

        let escapedValue = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escapedValue)\""
    }
}

private struct EventKey: Hashable {
    let sessionId: UUID
    let timestamp: Date
}
