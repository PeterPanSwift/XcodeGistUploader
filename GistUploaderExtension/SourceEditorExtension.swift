import Foundation
import XcodeKit

/// 指令清單改用 Info.plist 的 XCSourceEditorCommandDefinitions 靜態宣告，
/// 這裡不覆寫 commandDefinitions（Xcode 27 beta 對動態提供的支援有問題）。
class SourceEditorExtension: NSObject, XCSourceEditorExtension {
}
