import SwiftUI

struct SettingsView: View {
    // MARK: - Appearance Settings
    @AppStorage("appearance_mode") private var appearanceMode: String = "System Preference"
    @AppStorage("appearance_fontSize") private var fontSize: Double = 13.0
    @AppStorage("appearance_showLineNumbers") private var showLineNumbers: Bool = true
    
    // MARK: - Editor Settings
    @AppStorage("editor_autoIndentation") private var autoIndentation: Bool = true
    @AppStorage("editor_autoCloseBrackets") private var autoCloseBrackets: Bool = true
    @AppStorage("editor_autoCloseQuotes") private var autoCloseQuotes: Bool = true
    @AppStorage("editor_wordWrap") private var wordWrap: Bool = false
    @AppStorage("editor_tabWidth") private var tabWidth: Int = 4
    @AppStorage("editor_useSpaces") private var useSpacesInsteadOfTabs: Bool = true
    
    // MARK: - Files Settings
    @AppStorage("files_autoSave") private var autoSave: Bool = true
    @AppStorage("files_trimWhitespace") private var trimTrailingWhitespace: Bool = true
    
    // MARK: - Compiler Settings
    @AppStorage("compiler_defaultLanguage") private var defaultLanguage: String = "C++"
    @AppStorage("compiler_showBuildTime") private var showBuildTime: Bool = false
    @AppStorage("compiler_executionTimeout") private var executionTimeout: Int = 10

    // Filtered lists
    let appearances = ["System Preference", "Light Mode", "Dark Mode"]
    let languages = ["C", "C++", "Java"]
    
    var body: some View {
        Form {
            // MARK: - Appearance Section
            Section(header: Text("Appearance")) {
                Picker("Appearance Mode", selection: $appearanceMode) {
                    ForEach(appearances, id: \.self) { Text($0) }
                }
                
                Stepper(value: $fontSize, in: 9...24, step: 1) {
                    HStack {
                        Text("Editor Font Size")
                        Spacer()
                        Text("\(Int(fontSize)) pt").foregroundColor(.secondary)
                    }
                }
                
                Toggle("Show Line Numbers", isOn: $showLineNumbers)
            }
            
            // MARK: - Editor Section
            Section(header: Text("Editor")) {
                Toggle("Auto Indentation", isOn: $autoIndentation)
                Toggle("Auto Close Brackets", isOn: $autoCloseBrackets)
                Toggle("Auto Close Quotes", isOn: $autoCloseQuotes)
                Toggle("Word Wrap", isOn: $wordWrap)
                
                Picker("Tab Width", selection: $tabWidth) {
                    Text("2 Spaces").tag(2)
                    Text("4 Spaces").tag(4)
                    Text("8 Spaces").tag(8)
                }
                
                Toggle("Use Spaces Instead of Tabs", isOn: $useSpacesInsteadOfTabs)
            }
            
            // MARK: - Files Section
            Section(header: Text("Files")) {
                Toggle("Auto Save", isOn: $autoSave)
                Toggle("Trim Trailing Whitespace", isOn: $trimTrailingWhitespace)
            }
            
            // MARK: - Compiler Section
            Section(header: Text("Compiler")) {
                Picker("Default Language", selection: $defaultLanguage) {
                    ForEach(languages, id: \.self) { Text($0) }
                }
                
                Toggle("Show Build Time", isOn: $showBuildTime)
                
                Stepper(value: $executionTimeout, in: 1...60) {
                    HStack {
                        Text("Execution Timeout")
                        Spacer()
                        Text("\(executionTimeout)s").foregroundColor(.secondary)
                    }
                }
            }
            
            // MARK: - About Section (No GitHub Link)
            Section(header: Text("About")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("2.0.0 (Final)").foregroundColor(.secondary)
                }
                
                HStack {
                    Text("License")
                    Spacer()
                    Text("MIT License").foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 410, minHeight: 550)
        // Dynamically shift app color rendering themes natively on window focus
        .onChange(of: appearanceMode) { oldValue, newValue in
            applyAppearance(newValue)
        }
    }
    
    private func applyAppearance(_ mode: String) {
        DispatchQueue.main.async {
            switch mode {
            case "Light Mode":
                NSApp.appearance = NSAppearance(named: .aqua)
            case "Dark Mode":
                NSApp.appearance = NSAppearance(named: .darkAqua)
            default:
                NSApp.appearance = nil // Follows system global preference
            }
        }
    }
}
