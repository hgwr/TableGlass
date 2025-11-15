import Foundation

public protocol SSHConfigAliasProvider: Sendable {
    func availableAliases() async throws -> [String]
}

public struct DefaultSSHConfigAliasProvider: SSHConfigAliasProvider {
    private let configURL: URL

    public init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config")
    ) {
        self.configURL = configURL
    }

    public func availableAliases() async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            guard manager.fileExists(atPath: configURL.path) else {
                return []
            }

            let data = try Data(contentsOf: configURL)
            guard let contents = String(data: data, encoding: .utf8) else {
                return []
            }

            return SSHConfigParser.parseHostAliases(from: contents)
        }.value
    }
}

public enum SSHConfigParser {
    public static func parseHostAliases(from contents: String) -> [String] {
        var ordered: [String] = []
        var membership = Set<String>()

        contents.components(separatedBy: CharacterSet.newlines).forEach { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                return
            }

            let components = line.split(whereSeparator: { $0.isWhitespace })
            guard let first = components.first?.lowercased(), first == "host" else {
                return
            }

            let aliasTokens = components.dropFirst().map { String($0) }
            guard Self.aliasTokensArePlain(aliasTokens) else {
                return
            }

            for alias in aliasTokens {
                if membership.insert(alias).inserted {
                    ordered.append(alias)
                }
            }
        }

        return ordered
    }

    private static func aliasTokensArePlain(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }

        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            guard trimmed.rangeOfCharacter(from: disallowedCharacters) == nil else {
                return false
            }
            guard trimmed.rangeOfCharacter(from: allowedCharacterSet.inverted) == nil else {
                return false
            }
        }

        return true
    }

    private static let disallowedCharacters = CharacterSet(charactersIn: "*?!,")
    private static let allowedCharacterSet: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "._-")
        return set
    }()
}
