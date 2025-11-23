import Foundation

public enum DatabaseError: LocalizedError, Sendable, Equatable {
    case connectionFailed(String)
    case queryFailed(String)
    case transactionFailed(String)
    case invalidConfiguration(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return message
        case .queryFailed(let message):
            return message
        case .transactionFailed(let message):
            return message
        case .invalidConfiguration(let message):
            return message
        case .cancelled:
            return "The operation was cancelled."
        }
    }
}
