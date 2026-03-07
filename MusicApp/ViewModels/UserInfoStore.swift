import Foundation
import Combine

@MainActor
final class UserInfoStore: ObservableObject {
    @Published var user: AppUser

    init(user: AppUser = AppUser(username: "LinhLe", avatarSymbol: "person.crop.circle.fill", appVersion: "1.0.0")) {
        self.user = user
    }
}

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

    func signInDemo() {
        currentUser = authRepository.signInDemo()
    }

    func signOut() {
        authRepository.signOut()
        currentUser = nil
    }
}
