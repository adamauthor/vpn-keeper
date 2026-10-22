import Carbon.HIToolbox
import Foundation

@MainActor
enum PasswordKeyboard {
    /// Choose the user's most recently used enabled English input source.
    /// This changes the keyboard layout only; it never reads or rewrites text.
    static func selectEnglish() -> Bool {
        guard let source = TISCopyInputSourceForLanguage("en" as CFString)?.takeRetainedValue() else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }
}
