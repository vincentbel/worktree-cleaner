import Foundation

enum CoreL10n {
  static func format(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Bundle.module.localizedString(forKey: key, value: key, table: nil)
    return String(format: format, locale: .current, arguments: arguments)
  }
}
