import Foundation

enum Localizer {
    static func string(_ key: String, language: AppLanguage) -> String {
        let code = language.code
        guard
            let path = Bundle.main.path(forResource: code, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, comment: "")
        }

        return NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }
}
