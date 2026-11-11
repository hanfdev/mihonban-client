import Foundation
import Observation

@MainActor @Observable
final class SessionStore {
    private(set) var client: APIClient?
    private(set) var info: SessionInfo?
    private(set) var revision = UUID()
    private(set) var authorizationRevision = UUID()
    private(set) var needsSignIn = false
    @ObservationIgnored private var renewal: Task<SessionInfo, Error>?
    @ObservationIgnored var authorizationRejected: ((URL) -> Void)?
    @ObservationIgnored var authorizationChanged: (() -> Void)?
    var isAdmin: Bool { info?.role == "admin" }
    var canSeeHidden: Bool { isAdmin || info?.role == "companion" }

    func connect(_ client: APIClient, info: SessionInfo) {
        invalidate()
        self.client = client
        self.info = info
        needsSignIn = false
    }

    func invalidate() {
        revision = UUID()
        authorizationRevision = UUID()
        renewal?.cancel()
        renewal = nil
        client = nil
        info = nil
    }

    // All callers share a single password renewal, and never retry writes after
    // transport failures. Only an explicit 401 permits one authenticated retry.
    func perform<Value: Sendable>(_ operation: @escaping @Sendable (APIClient) async throws -> Value) async throws -> Value {
        guard let client else { throw ClientError.sessionExpired }
        let token = revision
        do {
            try Task.checkCancellation()
            let value = try await operation(client)
            try Task.checkCancellation()
            guard token == revision else { throw CancellationError() }
            return value
        } catch {
            if isRequestCancellation(error) || Task.isCancelled || token != revision { throw CancellationError() }
            guard Self.isExpired(error) else { throw error }
            let renewed: SessionInfo
            do {
                renewed = try await renew(client, token: token)
                try Task.checkCancellation()
                guard token == revision else { throw CancellationError() }
            } catch {
                if isRequestCancellation(error) || Task.isCancelled || token != revision { throw CancellationError() }
                if isRejected(error) { rejectAuthorization(client, token: token) }
                throw error
            }
            let changed = info?.role != renewed.role || info?.guest != renewed.guest
            info = renewed
            if changed {
                // Retire permission-scoped UI and caches before retrying. Keep
                // the request revision so shared renewal waiters can continue.
                authorizationRevision = UUID()
                authorizationChanged?()
            }
            do {
                try Task.checkCancellation()
                let value = try await operation(client)
                try Task.checkCancellation()
                guard token == revision else { throw CancellationError() }
                return value
            } catch {
                if isRequestCancellation(error) || Task.isCancelled || token != revision { throw CancellationError() }
                // A retried request may fail for transport or resource permissions
                // even though renewal succeeded. Only session rejection signs out.
                if Self.isExpired(error) { rejectAuthorization(client, token: token) }
                throw error
            }
        }
    }

    private static func isExpired(_ error: Error) -> Bool {
        (error as? ServerError)?.status == 401 || (error as? ClientError)?.key == "mobile.sessionExpired"
    }

    private func rejectAuthorization(_ client: APIClient, token: UUID) {
        guard token == revision, !needsSignIn else { return }
        needsSignIn = true
        authorizationRejected?(client.baseURL)
    }

    private func renew(_ client: APIClient, token: UUID) async throws -> SessionInfo {
        if let renewal { return try await renewal.value }
        guard let password = CredentialStore.read(for: client.baseURL.absoluteString) else {
            throw ClientError.sessionExpired
        }
        let task = Task {
            let result = try await client.login(password: password)
            guard result.ok else { throw ClientError.sessionExpired }
            return result
        }
        renewal = task
        defer { if token == revision { renewal = nil } }
        return try await task.value
    }
}
