import Foundation

@main
struct DisplayRevisionTests {
    static func main() throws {
        let tracker = ObservationRevisionTracker()
        let displayA = Data([1])
        let displayB = Data([2])
        let windowA = Data([3])

        let firstDisplay = try tracker.revision(for: .displays, fingerprint: displayA)
        let unchangedDisplay = try tracker.revision(for: .displays, fingerprint: displayA)
        let firstWindow = try tracker.revision(for: .windows, fingerprint: windowA)
        let unchangedWindow = try tracker.revision(for: .windows, fingerprint: windowA)
        let changedDisplay = try tracker.revision(for: .displays, fingerprint: displayB)

        precondition(firstDisplay == 1)
        precondition(unchangedDisplay == firstDisplay)
        precondition(firstWindow > firstDisplay)
        precondition(unchangedWindow == firstWindow)
        precondition(changedDisplay > firstWindow)
        print("DisplayRevisionTests passed")
    }
}
