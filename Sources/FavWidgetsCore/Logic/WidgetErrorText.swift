import Foundation

/// What a widget shows when a load fails (2026-10-12). A cancelled request
/// (its screen went away, or another load replaced it) is not a failure and
/// is never shown: "cancelled" in yellow under the Events card was one.
/// Everything else gets a sentence a person can act on, not a raw
/// system string.
public enum WidgetErrorText {
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    /// nil for a cancellation; otherwise what to show.
    public static func message(for error: Error) -> String? {
        if isCancellation(error) { return nil }
        if let api = error as? WidgetAPIError, !api.message.isEmpty, api.status != 0 { return api.message }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed:
                return "Couldn't connect. Pull down to try again."
            default: break
            }
        }
        return "Something went wrong. Pull down to try again."
    }
}
