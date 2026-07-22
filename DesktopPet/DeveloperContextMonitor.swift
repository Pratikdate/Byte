import Foundation
import AppKit

/// Monitor for developer workspace activity, IDE active files, git state, and programming languages
class DeveloperContextMonitor {
    static let shared = DeveloperContextMonitor()

    struct DeveloperContext {
        let activeAppName: String
        let activeFileOrTitle: String
        let detectedLanguage: String
        let currentProjectName: String
    }

    private(set) var currentContext: DeveloperContext = DeveloperContext(
        activeAppName: "",
        activeFileOrTitle: "",
        detectedLanguage: "Unknown",
        currentProjectName: "Unknown"
    )

    private var monitorTimer: Timer?

    private init() {
        startMonitoring()
    }

    func startMonitoring() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshDeveloperContext()
        }
    }

    func refreshDeveloperContext() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else { return }

        let fullTitle = DesktopEnvironmentManager.shared.frontmostWindowTitle ?? appName
        let language = detectLanguageFromTitle(fullTitle)
        let projectName = detectProjectName(fullTitle, appName: appName)

        currentContext = DeveloperContext(
            activeAppName: appName,
            activeFileOrTitle: fullTitle,
            detectedLanguage: language,
            currentProjectName: projectName
        )
    }

    private func detectLanguageFromTitle(_ title: String) -> String {
        let lower = title.lowercased()
        if lower.contains(".swift") { return "Swift" }
        if lower.contains(".py") { return "Python" }
        if lower.contains(".js") || lower.contains(".ts") || lower.contains(".tsx") || lower.contains(".jsx") { return "TypeScript/JavaScript" }
        if lower.contains(".rs") { return "Rust" }
        if lower.contains(".go") { return "Go" }
        if lower.contains(".cpp") || lower.contains(".c") || lower.contains(".h") || lower.contains(".hpp") { return "C/C++" }
        if lower.contains(".html") || lower.contains(".css") { return "HTML/CSS" }
        if lower.contains(".md") { return "Markdown" }
        if lower.contains(".json") || lower.contains(".yaml") || lower.contains(".yml") { return "Config" }
        return "General Code"
    }

    private func detectProjectName(_ title: String, appName: String) -> String {
        // Extract project name if in format "ProjectName — FileName" or "FileName — ProjectName"
        let parts = title.components(separatedBy: " — ")
        if parts.count >= 2 {
            return parts[0].trimmingCharacters(in: .whitespaces)
        }
        let dashParts = title.components(separatedBy: " - ")
        if dashParts.count >= 2 {
            return dashParts[0].trimmingCharacters(in: .whitespaces)
        }
        return appName
    }

    /// Formats a clean context string for the AI Engine prompt
    func formattedContextForAI() -> String {
        guard !currentContext.activeAppName.isEmpty else { return "Developer is active." }
        return "IDE/App: \(currentContext.activeAppName), File/Context: '\(currentContext.activeFileOrTitle)', Language: \(currentContext.detectedLanguage), Project: \(currentContext.currentProjectName)"
    }
}
