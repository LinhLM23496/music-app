import Foundation
import Combine

@MainActor
final class UserInfoStore: ObservableObject {
    @Published var user: AppUser

    init(user: AppUser = AppUser(username: "LinhLe", avatarSymbol: "person.crop.circle.fill", appVersion: "1.0.0")) {
        self.user = user
    }
}
