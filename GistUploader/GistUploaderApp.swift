import AppKit
import SwiftUI

@main
struct GistUploaderApp: App {
    @StateObject private var uploader = GistUploader()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(uploader)
                .onOpenURL { url in
                    uploader.handle(url: url)
                }
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - Upload state

enum UploadState: Equatable {
    case idle
    case uploading(filename: String)
    case success(url: String)
    case failure(message: String)
}

/// 接收 extension 傳來的 gistuploader://upload?file=...&name=...，
/// 讀取暫存檔後用 gh CLI 建立 gist。
@MainActor
final class GistUploader: ObservableObject {
    @Published var state: UploadState = .idle

    func handle(url: URL) {
        guard url.scheme == "gistuploader", url.host == "upload",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let filePath = components.queryItems?.first(where: { $0.name == "file" })?.value,
              let filename = components.queryItems?.first(where: { $0.name == "name" })?.value else {
            state = .failure(message: "收到無法解析的 URL：\(url)")
            return
        }

        // 只接受 extension sandbox 容器內的暫存檔，避免被其他程式濫用
        guard filePath.contains("/Containers/com.swiftruru.GistUploader.Extension/") else {
            state = .failure(message: "拒絕來源不明的檔案路徑。")
            return
        }

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            state = .failure(message: "讀不到暫存檔：\(filePath)")
            return
        }
        try? FileManager.default.removeItem(atPath: filePath)

        let kind = components.queryItems?.first(where: { $0.name == "kind" })?.value
        state = .uploading(filename: filename)

        Task.detached(priority: .userInitiated) {
            do {
                // 整檔上傳時，用 AppleScript 問 Xcode 目前的檔名（XcodeKit 不提供檔名）
                var finalName = filename
                if kind == "file", let realName = Self.xcodeFrontmostFileName() {
                    finalName = realName
                    await MainActor.run { self.state = .uploading(filename: realName) }
                }
                let gistURL = try Self.createGist(content: content, filename: finalName)
                await MainActor.run {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(gistURL, forType: .string)
                    self.state = .success(url: gistURL)
                }
                Self.notify(title: "Gist 上傳成功", message: "\(gistURL)（已複製到剪貼簿）")
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    self.state = .failure(message: message)
                }
                Self.notify(title: "Gist 上傳失敗", message: message)
            }
        }
    }

    // MARK: - gh

    private nonisolated static func createGist(content: String, filename: String) throws -> String {
        guard let gh = ghExecutablePath() else {
            throw makeError("找不到 gh 指令。請先安裝 GitHub CLI：brew install gh，並執行 gh auth login。")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["gist", "create", "-",
                             "--filename", filename,
                             "--desc", "Uploaded from Xcode"]

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        if let data = content.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw makeError(message.isEmpty
                            ? "gh gist create 失敗（exit \(process.terminationStatus)）。"
                            : "gh gist create 失敗：\(message)")
        }

        let output = String(data: stdoutData, encoding: .utf8) ?? ""
        guard let url = output
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { $0.hasPrefix("http") }) else {
            throw makeError("gh 執行成功但找不到 gist 網址。輸出：\(output)")
        }
        return url
    }

    /// 從 Xcode 最前方視窗標題（例如「MyApp — ContentView.swift」）取出目前編輯中的檔名。
    /// 需要「自動化」權限，第一次會跳系統詢問；失敗就回傳 nil，改用預設檔名。
    private nonisolated static func xcodeFrontmostFileName() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Xcode\" to get name of front window"]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let title = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }

        let candidates = title.components(separatedBy: " — ").filter { part in
            part != "Edited"
                && part.range(of: #"^[^/\\]+\.[A-Za-z0-9_+\-]+$"#,
                              options: .regularExpression) != nil
        }
        return candidates.last
    }

    private nonisolated static func ghExecutablePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private nonisolated static func notify(title: String, message: String) {
        func escaped(_ string: String) -> String {
            string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "display notification \"\(escaped(message))\" with title \"\(escaped(title))\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private nonisolated static func makeError(_ message: String) -> NSError {
        NSError(domain: "GistUploader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - UI

struct ContentView: View {
    @EnvironmentObject private var uploader: GistUploader

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Gist Uploader for Xcode")
                .font(.title2)
                .bold()

            statusView

            Divider()

            Text("啟用步驟")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text("1. 打開「系統設定 → 一般 → 登入項目與延伸功能 → Xcode Source Editor」，勾選 Gist Uploader。")
                Text("2. 重新啟動 Xcode，在 Editor 選單最下方會出現 Gist Uploader。")
                Text("3. 記得先在終端機用 gh auth login 登入 GitHub CLI。")
            }
            .foregroundStyle(.secondary)

            Divider()

            Text("指令說明")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text("• Upload File to Gist：上傳整個檔案內容。")
                Text("• Upload Selection to Gist：只上傳選取的程式碼。")
                Text("上傳成功後 gist 網址會自動複製到剪貼簿。")
            }
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 540)
    }

    @ViewBuilder
    private var statusView: some View {
        switch uploader.state {
        case .idle:
            Text("等待中——從 Xcode 的 Editor 選單觸發上傳。")
                .foregroundStyle(.secondary)
        case .uploading(let filename):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在上傳 \(filename)…")
            }
        case .success(let url):
            VStack(alignment: .leading, spacing: 6) {
                Label("上傳成功（網址已複製到剪貼簿）", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let link = URL(string: url) {
                    Link(url, destination: link)
                        .textSelection(.enabled)
                } else {
                    Text(url).textSelection(.enabled)
                }
            }
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}
