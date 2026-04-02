import Foundation

protocol DownloadJobStoring {
    func loadJobs() -> [DownloadJob]
    func saveJobs(_ jobs: [DownloadJob])
}

final class UserDefaultsDownloadJobStore: DownloadJobStoring {
    private enum Keys {
        static let jobs = "download.jobs"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadJobs() -> [DownloadJob] {
        guard
            let data = defaults.data(forKey: Keys.jobs),
            let jobs = try? JSONDecoder().decode([DownloadJob].self, from: data)
        else {
            return []
        }
        return jobs
    }

    func saveJobs(_ jobs: [DownloadJob]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        defaults.set(data, forKey: Keys.jobs)
    }
}
