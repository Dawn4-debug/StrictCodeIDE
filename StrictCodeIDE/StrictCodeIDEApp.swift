//
//  StrictCodeIDEApp.swift
//  StrictCodeIDE
//
//  Created by Shrish Agavane on 09/07/26.
//
import SwiftUI

@main
struct StrictCodeIDEApp: App {
    // Keeping trace of your existing AppDelegate or ViewModels if present
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        // This structural block links your settings panel directly into macOS system preferences
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
