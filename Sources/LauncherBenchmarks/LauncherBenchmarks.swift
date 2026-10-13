import Foundation
import LauncherCore

@main
struct LauncherBenchmarks {
    struct Scenario: Codable {
        let name: String
        let samplesMilliseconds: [Double]
        let resultCount: Int
        let checksum: Int
    }
    struct Report: Codable {
        let generatedAt: Date
        let recordCount: Int
        let warmupCount: Int
        let scenarios: [Scenario]
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw BenchmarkError.usage
        }
        let records = (0..<1_000).map { index in
            ApplicationRecord(
                id: "app-\(index)", name: String(format: "Application %04d", index),
                bundleIdentifier: "benchmark.app\(index)",
                url: URL(fileURLWithPath: "/synthetic/Application\(index).app"))
        }
        let index = SearchIndex(records: records)
        let queries = [
            ("exact", "Application 0500"),
            ("prefix", "005"),
            ("broad", "application"),
            ("fuzzy-miss", "xxxxxxxxxxxxxxx"),
        ]
        let scenarios = queries.map { name, query in
            measure(name: name, query: query, index: index)
        }
        let report = Report(
            generatedAt: Date(), recordCount: records.count,
            warmupCount: 100, scenarios: scenarios)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(
            to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
    }

    @inline(never)
    private static func measure(name: String, query: String, index: SearchIndex) -> Scenario {
        var checksum = 0
        var resultCount = 0
        for _ in 0..<100 { checksum &+= index.search(query).count }
        var samples: [Double] = []
        samples.reserveCapacity(1_000)
        for _ in 0..<1_000 {
            let start = ContinuousClock.now
            let results = index.search(query)
            let elapsed = start.duration(to: .now).components
            samples.append(
                Double(elapsed.seconds) * 1_000
                    + Double(elapsed.attoseconds) / 1_000_000_000_000_000)
            resultCount = results.count
            checksum &+= results.reduce(0) { $0 &+ $1.id.utf8.count &+ $1.matchKind.rawValue }
        }
        return Scenario(
            name: name, samplesMilliseconds: samples,
            resultCount: resultCount, checksum: checksum)
    }

    enum BenchmarkError: Error {
        case usage
    }
}
