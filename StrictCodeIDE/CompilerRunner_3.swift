import Foundation

enum SupportedLanguage: String, CaseIterable {
    case c = "C"
    case cpp = "C++"
    case java = "Java"

    var sourceExtension: String {
        switch self {
        case .c: return "c"
        case .cpp: return "cpp"
        case .java: return "java"
        }
    }

    /// Java requires the public class name to match the filename exactly,
    /// so we always name student Java files "Main.java" and require them
    /// to write `public class Main { ... }`.
    var sourceFileName: String {
        switch self {
        case .java: return "Main.java"
        default: return "main.\(sourceExtension)"
        }
    }
}

/// Swift's `Result` requires its failure type to conform to `Error` — a
/// plain `String` doesn't, so this thin wrapper carries the message.
struct CompileError: Error {
    let message: String
}

/// A successfully compiled program, ready to be run one or more times
/// (e.g. once per test case) without recompiling.
struct CompiledArtifact {
    let workDir: URL
    let runExecutable: String
    let runArguments: [String]
}

/// Compiles and runs student code in an isolated temp directory.
/// C/C++ compile through `xcrun clang`/`xcrun clang++` rather than calling
/// the compiler binaries directly — `xcrun` resolves the correct SDK and
/// standard library paths, which a bare `/usr/bin/clang++` invocation from
/// a GUI app doesn't reliably get, causing "undefined symbols" linker
/// errors for things like std::cout.
/// The RUN step (not compile) is wrapped in `sandbox-exec` — see
/// `SandboxProfile.swift` — so student binaries can't touch the network
/// or write files outside their own temp directory.
final class CompilerRunner {
    
    // MARK: - Dynamic Settings Hooks
    
    var executionTimeout: Int {
        let savedTimeout = UserDefaults.standard.integer(forKey: "compiler_executionTimeout")
        return savedTimeout == 0 ? 10 : savedTimeout // Falls back to 10 seconds if unset
    }
    
    var defaultLanguage: String {
        let lang = UserDefaults.standard.string(forKey: "compiler_defaultLanguage") ?? "C++"
        // Keeps it strictly restricted to your 3 required languages
        if lang == "C" || lang == "C++" || lang == "Java" {
            return lang
        }
        return "C++"
    }
    
    var showBuildTime: Bool {
        return UserDefaults.standard.bool(forKey: "compiler_showBuildTime")
    }
    
    /// Finds the real javac/java paths on this machine, since Java is never
    /// at a fixed location like clang is.
    private func locateJavaTool(_ tool: String) -> String? {
        let javaHomeResult = runProcess(executable: "/usr/libexec/java_home", arguments: [])
        if javaHomeResult.success {
            let jdkPath = javaHomeResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = jdkPath + "/bin/\(tool)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        let fallbackPaths = [
            "/opt/homebrew/opt/openjdk/bin/\(tool)",
            "/usr/local/opt/openjdk/bin/\(tool)",
            "/usr/bin/\(tool)"
        ]
        for path in fallbackPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    // MARK: - Single run (used by the main Run button)

    func compileAndRun(code: String, language: SupportedLanguage, stdin: String = "", completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // ⏱️ Start benchmark timer
            let startTime = CFAbsoluteTimeGetCurrent()
            let compileResult = self.compile(code: code, language: language)
            let buildDuration = CFAbsoluteTimeGetCurrent() - startTime
            
            switch compileResult {
            case .failure(let error):
                completion(error.message)
            case .success(let artifact):
                let result = self.run(artifact: artifact, stdin: stdin)
                var finalOutput = result.output.isEmpty ? "✅ Ran with no output." : result.output
                
                // 💡 If turned on in settings, prepend the execution log output with the metrics
                if self.showBuildTime {
                    let formattedTime = String(format: "%.3f", buildDuration)
                    finalOutput = "⏱️ Build Time: \(formattedTime)s\n────────────────────────\n" + finalOutput
                }
                
                completion(finalOutput)
                try? FileManager.default.removeItem(at: artifact.workDir)
            }
        }
    }

    // MARK: - Batch run (used by Test Cases — compiles once, runs many inputs)

    func runTestCases(code: String, language: SupportedLanguage, testCases: [TestCase], completion: @escaping ([TestCaseResult]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            switch self.compile(code: code, language: language) {
            case .failure(let error):
                let results = testCases.map { TestCaseResult(testCase: $0, actualOutput: error.message, passed: false) }
                completion(results)
            case .success(let artifact):
                let results = testCases.map { testCase -> TestCaseResult in
                    let runResult = self.run(artifact: artifact, stdin: testCase.input)
                    let actual = runResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let expected = testCase.expectedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    return TestCaseResult(testCase: testCase, actualOutput: runResult.output, passed: runResult.success && actual == expected)
                }
                completion(results)
                try? FileManager.default.removeItem(at: artifact.workDir)
            }
        }
    }

    // MARK: - Compile step (shared)

    private func compile(code: String, language: SupportedLanguage) -> Result<CompiledArtifact, CompileError> {
        let workDir = makeTempDirectory()
        let sourceFile = workDir.appendingPathComponent(language.sourceFileName)
        let binaryFile = workDir.appendingPathComponent("main.out")

        do {
            try code.write(to: sourceFile, atomically: true, encoding: .utf8)
        } catch {
            return .failure(CompileError(message: "❌ Failed to write source file: \(error.localizedDescription)"))
        }

        switch language {
        case .c, .cpp:
            let compilerName = language == .c ? "clang" : "clang++"
            let compileResult = runProcess(
                executable: "/usr/bin/xcrun",
                arguments: [compilerName, sourceFile.path, "-o", binaryFile.path]
            )
            guard compileResult.success else {
                return .failure(CompileError(message: "❌ Compile error:\n\(compileResult.output)"))
            }
            return .success(CompiledArtifact(workDir: workDir, runExecutable: binaryFile.path, runArguments: []))

        case .java:
            guard let javacPath = locateJavaTool("javac"), let javaPath = locateJavaTool("java") else {
                return .failure(CompileError(message: "❌ No Java runtime found.\n\nInstall it with:\n  brew install openjdk\n\nThen restart the app."))
            }
            let compileResult = runProcess(executable: javacPath, arguments: [sourceFile.path])
            guard compileResult.success else {
                return .failure(CompileError(message: "❌ Compile error:\n\(compileResult.output)"))
            }
            return .success(CompiledArtifact(workDir: workDir, runExecutable: javaPath, runArguments: ["-cp", workDir.path, "Main"]))
        }
    }

    // MARK: - Run step (shared, sandboxed, supports stdin)

    private func run(artifact: CompiledArtifact, stdin: String) -> (success: Bool, output: String) {
        runSandboxed(
            executable: artifact.runExecutable,
            arguments: artifact.runArguments,
            workDir: artifact.workDir,
            stdin: stdin,
            timeout: TimeInterval(self.executionTimeout) // 💡 Linked directly to slider configurations
        )
    }

    /// Runs the given executable wrapped in `sandbox-exec`, restricted by
    /// the profile generated in `SandboxProfile.swift` — no network, no
    /// writes outside the temp working directory.
    private func runSandboxed(executable: String, arguments: [String], workDir: URL, stdin: String, timeout: TimeInterval) -> (success: Bool, output: String) {
        guard let profilePath = SandboxProfile.writeProfile(forWorkingDirectory: workDir) else {
            print("⚠️ Running WITHOUT sandbox — profile failed to write")
            return runProcess(executable: executable, arguments: arguments, stdin: stdin, timeout: timeout)
        }
        let sandboxArgs = ["-f", profilePath.path, executable] + arguments
        return runProcess(executable: "/usr/bin/sandbox-exec", arguments: sandboxArgs, stdin: stdin, timeout: timeout)
    }

    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrictCodeIDE-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func runProcess(executable: String, arguments: [String], stdin: String = "", timeout: TimeInterval = 10.0) -> (success: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let inputPipe = Pipe()
        process.standardInput = inputPipe

        do {
            try process.run()
        } catch {
            return (false, "Failed to launch process: \(error.localizedDescription)")
        }

        // Feed stdin (for test cases), then close it so a program reading
        // with scanf/Scanner sees EOF instead of hanging forever.
        if let data = stdin.data(using: .utf8), !data.isEmpty {
            inputPipe.fileHandleForWriting.write(data)
        }
        inputPipe.fileHandleForWriting.closeFile()

        let deadline = DispatchTime.now() + timeout
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            process.waitUntilExit()
            semaphore.signal()
        }
        if semaphore.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return (false, "⏱️ Timed out — possible infinite loop.")
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let outputString = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus == 0, outputString)
    }
}
