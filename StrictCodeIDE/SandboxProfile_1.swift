import Foundation

/// Builds a macOS `sandbox-exec` profile (Apple's built-in process sandboxing
/// tool) that we wrap around a STUDENT'S COMPILED BINARY when we run it —
/// not around our own app. This is separate from Xcode's "App Sandbox"
/// capability, which only affects our app itself.
///
/// The profile:
/// - Denies all network access (no sockets in or out)
/// - Denies filesystem writes everywhere except the program's own temp
///   working directory (so it can't touch the student's real files, or
///   anyone else's, on a shared lab machine)
/// - Allows read access broadly, since compiled binaries need to read
///   shared system libraries (and Java needs to read JDK files) to even
///   launch
///
/// `sandbox-exec` is technically deprecated by Apple in favor of the App
/// Sandbox entitlement system, but it remains the standard tool for exactly
/// this "restrict an arbitrary child process" use case and is still present
/// on all current macOS versions.
enum SandboxProfile {

    static func writeProfile(forWorkingDirectory workDir: URL) -> URL? {
        let profilePath = workDir.appendingPathComponent("restrict.sb")
        let escapedPath = workDir.path

        let profile = """
        (version 1)
        (deny default)

        ; Allow reading anywhere (needed to load dynamic libraries,
        ; JDK class files, system frameworks, etc.)
        (allow file-read*)

        ; Only allow writes inside this program's own temp working directory
        (allow file-write*
            (subpath "\(escapedPath)"))

        ; Explicitly deny all network activity — no sockets, no connections
        (deny network*)

        ; Allow the basics a process needs to actually run
        (allow process-fork)
        (allow process-exec)
        (allow sysctl-read)
        (allow mach-lookup)
        (allow iokit-open)
        """

        do {
            try profile.write(to: profilePath, atomically: true, encoding: .utf8)
            return profilePath
        } catch {
            print("⚠️ Failed to write sandbox profile: \(error.localizedDescription)")
            return nil
        }
    }
}
