import AppKit

/// Handles saving and opening student source files using native macOS
/// save/open panels — the same system UI Xcode itself uses.
enum FileManagerHelper {

    // 🌟 1. ADD THIS COMPUTED PROPERTY AT THE VERY TOP OF THE ENUM 🌟
    private static var trimTrailingWhitespace: Bool {
        // Defaults to true if the preference has not been written yet
        return UserDefaults.standard.object(forKey: "files_trimWhitespace") as? Bool ?? true
    }

    static func save(code: String, language: SupportedLanguage, currentURL: URL?, completion: @escaping (URL?) -> Void) {
        if let url = currentURL {
            writeAndReturn(code: code, to: url, completion: completion)
            return
        }
        saveAs(code: code, language: language, completion: completion)
    }

    static func saveAs(code: String, language: SupportedLanguage, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = "main.\(language.sourceExtension)"
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }
            writeAndReturn(code: code, to: url, completion: completion)
        }
    }

    static func exportText(content: String, suggestedFileName: String, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = suggestedFileName
        panel.canCreateDirectories = true
        panel.message = "Save your exam submission"

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }
            writeAndReturn(code: content, to: url, completion: completion)
        }
    }

    static func openFolder(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a project folder"

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }
            completion(url)
        }
    }

    static func open(completion: @escaping (String?, URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = []

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil, nil)
                return
            }
            do {
                let contents = try String(contentsOf: url, encoding: .utf8)
                completion(contents, url)
            } catch {
                print("⚠️ Failed to open file: \(error.localizedDescription)")
                completion(nil, nil)
            }
        }
    }

    // 🌟 2. REPLACE YOUR WRITEANDRETURN FUNCTION AT THE BOTTOM WITH THIS 🌟
    private static func writeAndReturn(code: String, to url: URL, completion: @escaping (URL?) -> Void) {
        var finalCode = code
        
        // Intercept string buffer and sanitize trailing whitespace if active in Settings
        if trimTrailingWhitespace {
            finalCode = code.components(separatedBy: .newlines)
                .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
                .joined(separator: "\n")
        }
        
        do {
            try finalCode.write(to: url, atomically: true, encoding: .utf8)
            completion(url)
        } catch {
            print("⚠️ Failed to save file: \(error.localizedDescription)")
            completion(nil)
        }
    }
}
