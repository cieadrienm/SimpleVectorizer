import Foundation

/// Version and build reported by SimpleVectorizer (status bar, About sheet, `--version`).
/// Both are stamped into the bundle's `Info.plist` by `Scripts/bundle.sh`.
struct AppVersion: Equatable, CustomStringConvertible, Sendable {
    static let defaultVersion = "0.7.8"

    let version: String
    let build: String?

    init(version: String = Self.defaultVersion, build: String? = nil) {
        self.version = version
        self.build = build
    }

    init(infoDictionary info: [String: Any]?) {
        func value(_ key: String) -> String? {
            guard let s = (info?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty, !s.hasPrefix("@") else { return nil }
            return s
        }
        self.init(version: value("CFBundleShortVersionString") ?? Self.defaultVersion, build: value("CFBundleVersion"))
    }

    static let current = AppVersion(infoDictionary: Bundle.main.bundleIdentifier == "net.cieadrienm.simplevectorizer" ? Bundle.main.infoDictionary : nil)

    var description: String { build.map { "\(version) (\($0))" } ?? version }
    var shortLabel: String { "v\(description)" }
    var cliLine: String { "SimpleVectorizer \(description)" }

    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        guard arguments.dropFirst().contains("--version") || arguments.dropFirst().contains("-v") else { return }
        print(current.cliLine)
        exit(0)
    }
}
