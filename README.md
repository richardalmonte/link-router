<div align="center">
  <img src="assets/AppIcon.png" width="128" height="128" alt="LinkRouter Logo" />
  <h1>LinkRouter for macOS</h1>
  <p><strong>A fast, privacy-first default browser router designed specifically for modern developers.</strong></p>
  <p>Route links to the right browser automatically — by calling application, CLI process tree, or target URL.</p>

  <p>
    <a href="https://developer.apple.com/swift/"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?style=flat&logo=swift&logoColor=white" alt="Swift" /></a>
    <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-12.0+-000000?style=flat&logo=apple&logoColor=white" alt="macOS" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat" alt="MIT License" /></a>
    <img src="https://img.shields.io/badge/Dependencies-Zero-success?style=flat" alt="Zero Dependencies" />
    <img src="https://img.shields.io/badge/Telemetry-Zero-brightgreen?style=flat" alt="Zero Telemetry" />
  </p>
</div>

---

## ⚡ The Problem

As developers, we frequently work across two distinct browser environments:

1. **The Work Browser** (e.g., Google Chrome or Edge) tied to enterprise SSO, Google Workspace, internal email, Slack, and corporate security profiles.
2. **The Development & AI Browser** (e.g., Comet, Brave, Arc, or Zen) tailored with ad-blockers, developer consoles, personal GitHub accounts, and AI research sessions.

Whenever you click a link in an IDE like **Antigravity**, **OpenCode**, **Cursor**, or **VS Code** — or when a terminal CLI triggers an OAuth callback — macOS opens your system-wide default browser, inadvertently polluting your corporate account and mixing environments.

Traditional browser switchers struggle with terminal commands and child process spawns because they only inspect the immediate caller or window title.

---

## 🚀 The Solution: Process Tree Traversal

**LinkRouter** replaces your default browser setting with a high-performance, native macOS agent written in pure Swift.

When a link is opened, LinkRouter:
* **Traverses the Process Tree:** Uses Darwin `proc_pidinfo` kernel APIs to trace parent process IDs (up to 12 generations). If a terminal command, plugin script, or OAuth helper was launched from Antigravity, OpenCode, or your terminal emulator, LinkRouter detects the root IDE and routes accordingly.
* **Inspects URL Patterns:** Instantly routes matching patterns (such as `localhost`, `127.0.0.1`, or local development domains) to your preferred browser regardless of origin.
* **Preserves Enterprise Workflows:** Leaves all links originating from Slack, Teams, Outlook, or corporate email undisturbed, sending them straight to your corporate browser.

---

## ✨ Highlights

* **100% Native Swift:** Built with AppKit and Darwin APIs without Electron, Node, or external dependencies.
* **Sub-Millisecond Routing:** Routes URLs in less than 2 milliseconds with memory usage under 10 MB.
* **Zero Telemetry:** Operates completely offline. Your browsing history and URLs never leave your machine.
* **Instant Config Updates:** Changes saved to `~/.config/link-router/config.json` apply immediately without restarting.
* **Built-in Diagnostics:** Optional logging lets you inspect caller process chains and routing decisions in real time.

---

## 📦 Quick Installation

### Option 1: One-Line Install Script
Clone the repository and run the installer:

```bash
git clone https://github.com/richardalmonte/link-router.git
cd link-router
./scripts/install.sh
```

The script compiles LinkRouter using `swiftc`, copies the app to `~/Applications/LinkRouter.app`, generates the default config, and registers the app with macOS LaunchServices.

### Option 2: Set as Default Browser
1. Open **System Settings** on your Mac.
2. Navigate to **Desktop & Dock** > **Default web browser**.
3. Select **LinkRouter** from the menu.

---

## ⚙️ Configuration (`~/.config/link-router/config.json`)

LinkRouter is configured using a straightforward JSON file located at `~/.config/link-router/config.json`:

```json
{
  "default_browser": "Google Chrome",
  "app_rules": {
    "Antigravity": "Comet",
    "OpenCode": "Comet",
    "Cursor": "Brave Browser",
    "Code": "Brave Browser",
    "Terminal": "Comet",
    "iTerm": "Comet",
    "Warp": "Comet",
    "Ghostty": "Comet"
  },
  "url_rules": {
    "localhost": "Comet",
    "127.0.0.1": "Comet",
    "dev.local": "Comet"
  },
  "force_account_picker": true,
  "logging": true
}
```

### Configuration Options:
* **`default_browser`**: Fallback browser when no other rule matches.
* **`app_rules`**: Mapping of application name, bundle ID, or parent process name to target browser.
* **`url_rules`**: Mapping of URL keywords or domain patterns to target browser.
* **`force_account_picker`**: *(Optional, default: `true`)* Automatically strips `login_hint` and sets `prompt=select_account` on OAuth authorization flows (e.g., Google). This stops IDEs and CLIs from locking plugin/connector logins to the account you use for the IDE.
* **`logging`**: Enables logging to `~/.config/link-router/router.log`.

### Rule Evaluation Order:
1. **URL Rules (`url_rules`):** Evaluated first. If the destination URL contains any configured keyword (case-insensitive), it routes to the specified browser.
2. **App Rules (`app_rules`):** Checked against the sender's bundle identifier, application name, and entire ancestor process chain.
3. **Default Browser (`default_browser`):** Used as a fallback for all unspecified apps (e.g., Slack, Mail, Messages).

---

## 🔍 Troubleshooting & Logs

You can inspect recent routing events and process chains anytime:

```bash
tail -f ~/.config/link-router/router.log
```

Example log output:
```text
[2026-11-10 22:11:03] [URL: https://github.com/...] [Source: open | Bundle: com.google.antigravity | Chain: open -> zsh -> language_server -> Antigravity] -> Routed to 'Comet' (via app_rule(Antigravity))
```

---

## 📄 License

Distributed under the [MIT License](LICENSE). Copyright &copy; 2026 Richard Almonte.
