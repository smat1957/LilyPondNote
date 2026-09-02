// macOS上のLilyPondコマンドを起動してPDFとコンパイルログを生成する。

import Foundation

actor macOSLocalLilyPondCompiler: LilyPondCompiling {
    private let executableLocator: macOSLilyPondExecutableLocator

    /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
    init(executableLocator: macOSLilyPondExecutableLocator = .init()) {
        self.executableLocator = executableLocator
    }

    /// 入力を処理して生成結果を返す。
    func compile(_ input: LilyPondCompilationInput) async throws
        -> LilyPondCompilationResult {
        guard let executableURL = executableLocator.locate() else {
            throw LilyPondCompilationError.executableNotFound
        }

        let manager = FileManager.default
        let workURL = manager.temporaryDirectory.appending(
            path: "LilyPondNote-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try manager.createDirectory(at: workURL, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: workURL) }

        try input.processingProgram.write(
            to: workURL.appending(path: ScoreFileSet.processingProgramFileName),
            atomically: true,
            encoding: .utf8
        )
        try input.scoreData.write(
            to: workURL.appending(path: ScoreFileSet.scoreDataFileName),
            atomically: true,
            encoding: .utf8
        )

        let runResult = try await run(executableURL, in: workURL)
        guard runResult.exitCode == 0 else {
            throw LilyPondCompilationError.executionFailed(
                exitCode: runResult.exitCode,
                log: runResult.log
            )
        }
        let pdfURL = workURL.appending(path: ScoreFileSet.pdfFileName)
        guard manager.fileExists(atPath: pdfURL.path) else {
            throw LilyPondCompilationError.pdfNotProduced(log: runResult.log)
        }
        let pdfData = try Data(contentsOf: pdfURL)
        return LilyPondCompilationResult(
            pdfData: pdfData,
            log: runResult.log,
            compilerVersion: LilyPondCompilerVersion.detected(inPDF: pdfData)
                ?? LilyPondCompilerVersion.detected(in: runResult.log)
                ?? String(localized: "不明")
        )
    }

    /// `run`が担当する処理を実行する。
    private func run(_ executableURL: URL, in workURL: URL) async throws
        -> (exitCode: Int32, log: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executableURL
            process.arguments = [
                "--pdf", "-o", "output",
                ScoreFileSet.processingProgramFileName
            ]
            process.currentDirectoryURL = workURL
            process.environment = environment(for: executableURL)
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (
                    process.terminationStatus,
                    String(decoding: data, as: UTF8.self)
                ))
            }
        }
    }

    /// GUI applications launched from Finder do not inherit the user's shell
    /// PATH. LilyPond starts Ghostscript as `gs`, so include the standard
    /// Homebrew locations explicitly while retaining the inherited PATH.
    private func environment(for executableURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let inheritedPaths = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let paths = [
            executableURL.deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ] + inheritedPaths

        var seen = Set<String>()
        environment["PATH"] = paths
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
        return environment
    }
}
