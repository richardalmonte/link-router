import Cocoa
import Darwin

/// Represents user routing rules and configuration for LinkRouter.
struct RouterConfig: Codable {
    /// Default fallback browser when no app or URL rule matches.
    var default_browser: String
    /// Key-value mapping of application names or bundle IDs to target browsers.
    var app_rules: [String: String]
    /// Key-value mapping of URL keywords or domain patterns to target browsers.
    var url_rules: [String: String]
    /// Forces OAuth providers (like Google) to show the account picker instead of locking to the IDE account.
    var force_account_picker: Bool?
    /// Whether link routing decisions should be recorded in router.log.
    var logging: Bool?
}

/// Core routing engine responsible for configuration management, caller inspection, and browser dispatch.
class LinkRouter {
    /// Shared singleton instance.
    static let shared = LinkRouter()
    
    /// Path to configuration directory (~/.config/link-router).
    let configDir: URL
    /// Path to config.json file.
    let configFile: URL
    /// Path to operational log file.
    let logFile: URL
    
    /// Initializes file paths and creates the configuration directory if needed.
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".config/link-router")
        configFile = configDir.appendingPathComponent("config.json")
        logFile = configDir.appendingPathComponent("router.log")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    }
    
    /// Loads the latest configuration from disk, with fallback defaults.
    func loadConfig() -> RouterConfig {
        if let data = try? Data(contentsOf: configFile),
           let cfg = try? JSONDecoder().decode(RouterConfig.self, from: data) {
            return cfg
        }
        return RouterConfig(
            default_browser: "Google Chrome",
            app_rules: [
                "Antigravity": "Comet",
                "OpenCode": "Comet",
                "Terminal": "Comet",
                "iTerm": "Comet"
            ],
            url_rules: [
                "localhost": "Comet",
                "127.0.0.1": "Comet"
            ],
            logging: true
        )
    }
    
    /// Appends an informational line to the router log file.
    /// - Parameter msg: The message string to write.
    func log(_ msg: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try? fileHandle.close()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
    
    /// Retrieves the executable name for a specific process ID using Darwin proc_pidinfo.
    /// - Parameter pid: The process identifier.
    /// - Returns: The process name string, or nil if unavailable.
    func getProcessName(pid: pid_t) -> String? {
        var procInfo = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &procInfo, Int32(size))
        guard result == size else { return nil }
        
        let nameWithNull = withUnsafeBytes(of: &procInfo.pbi_name) { rawPtr -> [CChar] in
            Array(rawPtr.bindMemory(to: CChar.self))
        }
        return String(cString: nameWithNull)
    }
    
    /// Retrieves the parent process ID for a given process identifier.
    /// - Parameter pid: The child process identifier.
    /// - Returns: The parent process identifier, or nil.
    func getParentPid(pid: pid_t) -> pid_t? {
        var procInfo = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &procInfo, Int32(size))
        guard result == size else { return nil }
        return pid_t(procInfo.pbi_ppid)
    }
    
    /// Traverses the ancestor process hierarchy to determine the true originating application.
    /// - Parameter event: The Apple Event received when the URL was triggered.
    /// - Returns: A tuple containing the resolved app name, bundle identifier, and process chain names.
    func resolveSenderInfo(event: NSAppleEventDescriptor?) -> (name: String, bundleId: String, chain: [String]) {
        var senderPid: pid_t = 0
        let myPid = getpid()
        
        if let event = event {
            // Priority 1: Extract sender PID from keySenderPIDAttr ('spid')
            if let pidDesc = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) {
                let pidVal = pidDesc.int32Value
                if pidVal > 0 && pidVal != myPid {
                    senderPid = pid_t(pidVal)
                }
            }
        }
        
        var chain: [String] = []
        var detectedBundleId = ""
        var detectedName = ""
        
        if senderPid > 0 {
            var cur = senderPid
            // Traverse parent processes to find the root IDE or terminal emulator
            for _ in 0..<12 {
                if cur <= 1 { break }
                if let app = NSRunningApplication(processIdentifier: cur) {
                    if detectedBundleId.isEmpty, let b = app.bundleIdentifier {
                        detectedBundleId = b
                    }
                    if let n = app.localizedName {
                        if detectedName.isEmpty { detectedName = n }
                        chain.append(n)
                    }
                } else if let pName = getProcessName(pid: cur) {
                    if detectedName.isEmpty { detectedName = pName }
                    chain.append(pName)
                }
                
                if let ppid = getParentPid(pid: cur) {
                    cur = ppid
                } else {
                    break
                }
            }
        }
        
        // Inspect frontmost app as fallback when the sender is a launch daemon
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != myPid {
            if let fn = front.localizedName, !chain.contains(fn) {
                chain.append("frontmost:\(fn)")
            }
            if detectedBundleId.isEmpty, let fb = front.bundleIdentifier {
                detectedBundleId = fb
            }
            if detectedName.isEmpty, let fn = front.localizedName {
                detectedName = fn
            }
        }
        
        return (detectedName, detectedBundleId, chain)
    }
    
    /// Sanitizes provider OAuth URLs to prevent the IDE from forcing its own account via login_hint.
    /// - Parameters:
    ///   - url: Originating authorization URL.
    ///   - enabled: Whether account picker forcing is active.
    /// - Returns: Cleaned URL with login_hint removed and select_account prompt enabled.
    func sanitizeOAuthURL(url: URL, enabled: Bool) -> URL {
        guard enabled else { return url }
        let urlStr = url.absoluteString
        guard urlStr.contains("accounts.google.com/o/oauth2") else {
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        // Remove login_hint to prevent provider from locking the login to the IDE account
        items.removeAll { $0.name.lowercased() == "login_hint" }
        // Force account selection prompt so the user can choose any account
        if let idx = items.firstIndex(where: { $0.name.lowercased() == "prompt" }) {
            items[idx].value = "select_account"
        } else {
            items.append(URLQueryItem(name: "prompt", value: "select_account"))
        }
        components.queryItems = items
        return components.url ?? url
    }
    
    /// Evaluates rules against the target URL and the sender hierarchy, dispatching to the chosen browser.
    /// - Parameters:
    ///   - url: The destination URL.
    ///   - event: Optional originating Apple Event descriptor.
    func route(url: URL, event: NSAppleEventDescriptor?) {
        let config = loadConfig()
        let finalURL = sanitizeOAuthURL(url: url, enabled: config.force_account_picker ?? true)
        let urlStr = finalURL.absoluteString
        let sender = resolveSenderInfo(event: event)
        
        var targetBrowser = config.default_browser
        var matchedRule = "default"
        
        // 1. Evaluate URL and domain match rules
        for (pattern, browser) in config.url_rules {
            if urlStr.localizedCaseInsensitiveContains(pattern) {
                targetBrowser = browser
                matchedRule = "url_rule(\(pattern))"
                break
            }
        }
        
        // 2. Evaluate caller process and bundle hierarchy rules
        if matchedRule == "default" {
            for (appPattern, browser) in config.app_rules {
                let lowerPattern = appPattern.lowercased()
                
                let matchesName = sender.name.lowercased().contains(lowerPattern)
                let matchesBundle = sender.bundleId.lowercased().contains(lowerPattern)
                let matchesChain = sender.chain.contains { $0.lowercased().contains(lowerPattern) }
                
                if matchesName || matchesBundle || matchesChain {
                    targetBrowser = browser
                    matchedRule = "app_rule(\(appPattern))"
                    break
                }
            }
        }
        
        if config.logging ?? true {
            let chainSummary = sender.chain.joined(separator: " -> ")
            log("[URL: \(urlStr)] [Source: \(sender.name) | Bundle: \(sender.bundleId) | Chain: \(chainSummary)] -> Routed to '\(targetBrowser)' (via \(matchedRule))")
        }
        
        openURL(finalURL, with: targetBrowser)
    }
    
    /// Opens the specified URL with a designated browser application.
    /// - Parameters:
    ///   - url: The web URL to open.
    ///   - browserName: Application name, bundle identifier, or absolute path.
    func openURL(_ url: URL, with browserName: String) {
        let ws = NSWorkspace.shared
        var appURL: URL? = nil
        
        if browserName.hasPrefix("/") {
            appURL = URL(fileURLWithPath: browserName)
        } else {
            let candidates = [
                "/Applications/\(browserName).app",
                "/Applications/\(browserName)",
                "\(NSHomeDirectory())/Applications/\(browserName).app",
                "/System/Applications/\(browserName).app"
            ]
            for path in candidates {
                if FileManager.default.fileExists(atPath: path) {
                    appURL = URL(fileURLWithPath: path)
                    break
                }
            }
            if appURL == nil {
                if let urlFound = ws.urlForApplication(withBundleIdentifier: browserName) {
                    appURL = urlFound
                }
            }
        }
        
        if let target = appURL {
            let conf = NSWorkspace.OpenConfiguration()
            conf.activates = true
            ws.open([url], withApplicationAt: target, configuration: conf) { _, error in
                if let error = error {
                    self.log("Error opening with \(target): \(error.localizedDescription). Falling back to CLI open.")
                    self.fallbackOpen(url: url, browserName: browserName)
                }
            }
        } else {
            fallbackOpen(url: url, browserName: browserName)
        }
    }
    
    /// Fallback launcher using the system /usr/bin/open command.
    /// - Parameters:
    ///   - url: The destination URL.
    ///   - browserName: Target browser application name.
    func fallbackOpen(url: URL, browserName: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", browserName, url.absoluteString]
        try? proc.run()
    }
}

/// Main application delegate handling Apple Events and background activation policy.
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Registers the system handler for kAEGetURL events before application finishes launching.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    /// Configures the app as an accessory (dockless) and prompts macOS default browser registration if needed.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http") { _ in
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https") { _ in }
        }
    }
    
    /// Dispatches incoming Apple Event URLs to the router engine.
    @objc func handleGetURL(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        LinkRouter.shared.route(url: url, event: event)
    }
    
    /// Handles standard open URL delegate requests.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            LinkRouter.shared.route(url: url, event: NSAppleEventManager.shared().currentAppleEvent)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
