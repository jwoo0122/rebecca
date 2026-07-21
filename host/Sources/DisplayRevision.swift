import Foundation

enum ObservationKind {
    case displays
    case windows
}

final class ObservationRevisionTracker {
    private var revisionValue: UInt64 = 0
    private var lastDisplayFingerprint: Data?
    private var lastWindowFingerprint: Data?

    func revision(for kind: ObservationKind, fingerprint: Data) throws -> UInt64 {
        let previous: Data?
        switch kind {
        case .displays:
            previous = lastDisplayFingerprint
        case .windows:
            previous = lastWindowFingerprint
        }
        if previous == fingerprint {
            return revisionValue
        }
        guard revisionValue < UInt64.max else {
            throw DisplayQueryError.failed("Observation revision exhausted.")
        }
        revisionValue += 1
        switch kind {
        case .displays:
            lastDisplayFingerprint = fingerprint
        case .windows:
            lastWindowFingerprint = fingerprint
        }
        return revisionValue
    }
}

func observationFingerprint<T: Encodable>(_ snapshot: T) throws -> Data {
    try JSONEncoder().encode(snapshot)
}
