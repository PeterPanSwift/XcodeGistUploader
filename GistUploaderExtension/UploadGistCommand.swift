import CoreServices
import Foundation
import UniformTypeIdentifiers
import XcodeKit

/// Sandbox 內不能執行 gh，所以這裡只負責把內容寫進暫存檔，
/// 再用 gistuploader:// URL scheme 交給容器 App 上傳。
class UploadGistCommand: NSObject, XCSourceEditorCommand {

    func perform(with invocation: XCSourceEditorCommandInvocation,
                 completionHandler: @escaping (Error?) -> Void) {
        let selectionOnly = invocation.commandIdentifier.hasSuffix(".UploadSelection")
        let buffer = invocation.buffer

        let content: String
        if selectionOnly {
            guard let selected = Self.selectedText(in: buffer) else {
                completionHandler(Self.makeError("沒有選取任何程式碼，請先選取要上傳的內容。"))
                return
            }
            content = selected
        } else {
            content = buffer.completeBuffer
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completionHandler(Self.makeError("內容是空的，沒有東西可以上傳。"))
            return
        }

        let filename = Self.suggestedFilename(contentUTI: buffer.contentUTI,
                                              selectionOnly: selectionOnly)

        do {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("gist-\(UUID().uuidString).txt")
            try content.write(to: fileURL, atomically: true, encoding: .utf8)

            var components = URLComponents()
            components.scheme = "gistuploader"
            components.host = "upload"
            components.queryItems = [
                URLQueryItem(name: "file", value: fileURL.path),
                URLQueryItem(name: "name", value: filename),
                URLQueryItem(name: "kind", value: selectionOnly ? "selection" : "file"),
            ]
            guard let url = components.url else {
                completionHandler(Self.makeError("無法組出 gistuploader:// URL。"))
                return
            }

            LSOpenCFURLRef(url as CFURL, nil)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    // MARK: - Buffer helpers

    private static func selectedText(in buffer: XCSourceTextBuffer) -> String? {
        var chunks: [String] = []

        for case let range as XCSourceTextRange in buffer.selections {
            // 游標（零長度選取）略過
            if range.start.line == range.end.line && range.start.column == range.end.column {
                continue
            }

            let lastLine = min(range.end.line, buffer.lines.count - 1)
            guard range.start.line <= lastLine else { continue }

            var lines: [String] = []
            for index in range.start.line...lastLine {
                guard var line = buffer.lines[index] as? String else { continue }
                // 先裁尾再裁頭，start 的位移才不會跑掉
                if index == range.end.line {
                    let end = line.index(line.startIndex,
                                         offsetBy: min(range.end.column, line.count))
                    line = String(line[line.startIndex..<end])
                }
                if index == range.start.line {
                    let start = line.index(line.startIndex,
                                           offsetBy: min(range.start.column, line.count))
                    line = String(line[start...])
                }
                lines.append(line)
            }
            chunks.append(lines.joined())
        }

        let result = chunks.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    private static func suggestedFilename(contentUTI: String, selectionOnly: Bool) -> String {
        let fileExtension = UTType(contentUTI)?.preferredFilenameExtension
            ?? fallbackExtension(forUTI: contentUTI)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())

        let base = selectionOnly ? "snippet" : "file"
        return "xcode-\(base)-\(timestamp).\(fileExtension)"
    }

    private static func fallbackExtension(forUTI uti: String) -> String {
        switch uti {
        case "public.swift-source": return "swift"
        case "public.objective-c-source": return "m"
        case "public.objective-c-plus-plus-source": return "mm"
        case "public.c-header": return "h"
        case "public.c-source": return "c"
        case "public.c-plus-plus-source": return "cpp"
        default: return "txt"
        }
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(domain: "GistUploader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
