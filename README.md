# Gist Uploader for Xcode

Upload the current file or selected code to a GitHub Gist straight from Xcode's Editor menu, powered by the [GitHub CLI](https://cli.github.com) (`gh`).

[English](#gist-uploader-for-xcode) | [中文說明](#gist-uploader-for-xcode-中文說明)

## Features

Two commands under **Editor → Gist Uploader**:

| Command | Description |
|---|---|
| Upload File to Gist | Uploads the whole file. The gist keeps the original file name. |
| Upload Selection to Gist | Uploads only the selected code (multiple selections supported). Named with a timestamp. |

On success the gist URL is copied to your clipboard and a notification pops up. Gists are created **secret** by default.

## Requirements

- macOS 14+, Xcode 14+
- GitHub CLI: `brew install gh`, then `gh auth login` (needs the `gist` scope)
- An Apple Developer Team ID (a free personal team works) — see [Signing](#signing)

## Install

1. Edit [Signing.xcconfig](Signing.xcconfig) and set `DEVELOPMENT_TEAM` to your own Team ID.
2. Run:

```bash
./install.sh
```

3. Check **Gist Uploader** in **System Settings → General → Login Items & Extensions → Xcode Source Editor**.
4. Restart Xcode. The commands appear at the bottom of the **Editor** menu whenever a source file has focus.

The script builds the Release configuration, installs `GistUploader.app` into `/Applications`, and registers the extension with PluginKit. Run it again any time you pull an update.

### Signing

A real Team ID is required — ad-hoc signing (`-`) does not work. `XcodeKit.framework` is embedded inside the `.appex`, and dyld refuses to load a nested library whose Team ID differs from the loading process; two unsigned ad-hoc identities do not count as matching.

Find your Team ID with:

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

and read the `OU` field, or look under Membership at developer.apple.com.

## Usage notes

- **Upload File to Gist** names the gist after the file you are editing. Since XcodeKit deliberately hides file names from extensions, the container app reads the front Xcode window title via AppleScript — the first upload triggers a one-time **Automation** permission prompt ("GistUploader wants to control Xcode"); allow it. If the lookup fails, a timestamped name is used instead.
- The container app briefly comes to the foreground during upload to show progress and the resulting URL.
- `gh` is looked up in `/opt/homebrew/bin`, `/usr/local/bin`, then `/usr/bin`.

## How it works

```
Xcode ─▶ GistUploaderExtension.appex (sandboxed)
             │  writes the code to a temp file
             ▼
        gistuploader://upload?file=…&name=…&kind=…
             │
             ▼
        GistUploader.app (not sandboxed)
             │  runs: gh gist create - --filename <name>
             ▼
        gist URL → clipboard + notification
```

The split exists because macOS refuses to register an app extension that is not sandboxed, while a sandboxed process cannot run `gh`. The app only accepts file paths inside the extension's own sandbox container, so the URL scheme cannot be abused by other processes.

## Notes for extension developers

Hard-won lessons from building this (macOS 27 / Xcode 27):

- The extension target's `productType` must be **`com.apple.product-type.xcode-extension`** — not the generic `app-extension`. With the wrong type the binary lacks the `XCExtensionSubsystem` linker glue, the log shows `misconfigured plugin; external subsystem [XCExtensionSubsystem] not present`, and the Editor menu shows a grayed-out name with no submenu.
- The appex **must have the App Sandbox entitlement** or `pkd` will not register it at all (`pluginkit -m` finds nothing).
- Keep the app in `/Applications` for reliable PluginKit discovery. Useful commands: `pluginkit -m -v -i <bundle-id>` (a leading `+` means enabled), `lsregister -f`, `pluginkit -a <appex>`.
- Keep the extension binary's linkage minimal (Foundation + XcodeKit), matching the template.
- `xcodebuild` auto-registers the build-directory app with LaunchServices, which produces duplicate entries in System Settings — `install.sh` unregisters it after installing.

## License

[MIT](LICENSE)

---

# Gist Uploader for Xcode（中文說明）

透過 [GitHub CLI](https://cli.github.com)（`gh`），直接在 Xcode 的 Editor 選單把目前檔案或選取的程式碼上傳成 GitHub Gist。

## 功能

**Editor → Gist Uploader** 底下有兩個指令：

| 指令 | 說明 |
|---|---|
| Upload File to Gist | 上傳整個檔案，gist 沿用原始檔名 |
| Upload Selection to Gist | 只上傳選取的程式碼（支援多重選取），以時間戳記命名 |

上傳成功後 gist 網址會自動複製到剪貼簿並跳出通知。預設建立 **secret gist**。

## 需求

- macOS 14+、Xcode 14+
- GitHub CLI：`brew install gh`，並執行 `gh auth login`（需要 `gist` scope）
- Apple Developer Team ID（免費的個人團隊即可）——見下方「簽章」

## 安裝

1. 編輯 [Signing.xcconfig](Signing.xcconfig)，把 `DEVELOPMENT_TEAM` 改成你自己的 Team ID。
2. 執行：

```bash
./install.sh
```

3. 到「**系統設定 → 一般 → 登入項目與延伸功能 → Xcode Source Editor**」勾選 **Gist Uploader**。
4. 重新啟動 Xcode，編輯器有焦點時 **Editor** 選單最下方就會出現指令。

腳本會建置 Release 版、把 `GistUploader.app` 安裝到 `/Applications` 並向 PluginKit 註冊。之後更新程式碼再跑一次即可。

### 簽章

必須使用真實的 Team ID，ad-hoc（`-`）簽章行不通：`XcodeKit.framework` 嵌在 `.appex` 裡，dyld 會拒絕載入 Team ID 與主程序不同的內嵌函式庫，而兩個未簽名的 ad-hoc 身分不算相同。

查 Team ID：

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

讀 `OU` 欄位，或到 developer.apple.com 的 Membership 頁面查看。

## 使用注意

- **Upload File to Gist** 會用你正在編輯的檔名。因為 XcodeKit 基於隱私不提供檔名，容器 App 會用 AppleScript 讀取 Xcode 最前方視窗標題——第一次上傳會跳出一次性的「**自動化**」權限詢問（GistUploader 想要控制 Xcode），請允許。若查詢失敗會改用時間戳記檔名。
- 上傳期間容器 App 會短暫跳到前景顯示進度與結果網址。
- `gh` 依序在 `/opt/homebrew/bin`、`/usr/local/bin`、`/usr/bin` 尋找。

## 運作原理

```
Xcode ─▶ GistUploaderExtension.appex（sandboxed）
             │  把程式碼寫進暫存檔
             ▼
        gistuploader://upload?file=…&name=…&kind=…
             │
             ▼
        GistUploader.app（未 sandbox）
             │  執行：gh gist create - --filename <name>
             ▼
        gist 網址 → 剪貼簿 + 通知
```

拆成兩塊是因為：macOS 不註冊未 sandbox 的 app extension，而 sandbox 內又不能執行 `gh`。App 只接受來自 extension 自己沙盒容器內的檔案路徑，URL scheme 不會被其他程式濫用。

## 給 extension 開發者的筆記

開發過程踩過的坑（macOS 27 / Xcode 27）：

- Extension target 的 `productType` 必須是 **`com.apple.product-type.xcode-extension`**，不能用一般的 `app-extension`。用錯的話執行檔會缺 `XCExtensionSubsystem` 連結膠水，log 出現 `misconfigured plugin; external subsystem [XCExtensionSubsystem] not present`，Editor 選單只會有反灰名字、沒有子選單。
- Appex **必須帶 App Sandbox entitlement**，否則 `pkd` 完全不註冊（`pluginkit -m` 查不到）。
- App 要放在 `/Applications`，PluginKit 才會可靠掃描。常用指令：`pluginkit -m -v -i <bundle-id>`（開頭 `+` 代表已啟用）、`lsregister -f`、`pluginkit -a <appex>`。
- Extension 執行檔的連結保持最小（Foundation + XcodeKit），和範本一致。
- `xcodebuild` 會自動把 build 目錄的 App 註冊進 LaunchServices，造成系統設定出現重複項目——`install.sh` 安裝後會幫忙取消註冊。

## 授權

[MIT](LICENSE)
