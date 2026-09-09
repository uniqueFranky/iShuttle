import Foundation

/// Port for persisting the authenticated HTTP session outside the presentation layer.
protocol SessionRepository {
    func restoreSession(into session: URLSession)
    func persistSession(from session: URLSession)
    func clearSession(from session: URLSession)
    func currentUsername() -> String?
    func saveUsername(_ username: String)
    func clearUsername()
}
