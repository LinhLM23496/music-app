import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var currentUser: AuthUser?

    private let authRepository: AuthRepository

    init(authRepository: AuthRepository) {
        self.authRepository = authRepository
        currentUser = authRepository.loadCurrentUser()
    }

    var isLoggedIn: Bool {
        currentUser != nil
    }

    var activeUser: AuthUser {
        currentUser ?? AuthUser.guest()
    }

    func signInDemo() {
        currentUser = authRepository.signInDemo()
    }

    func signOut() {
        authRepository.signOut()
        currentUser = nil
    }
}
