import Foundation

/// Well-known AI apps, offered whether or not any of your Macs has them yet.
public struct AIApp: Identifiable, Equatable {
    public enum Source: Equatable { case cask(String), appStore(String) }
    public var id: String
    public var name: String
    public var maker: String
    public var source: Source
    /// App bundles it installs, to tell whether it's on this Mac.
    public var appNames: [String]
    public var bundleIDs: [String]

    public var token: String {
        switch source {
        case .cask(let t): return "cask:" + t
        case .appStore(let id): return "mas:" + id
        }
    }
}

public enum AICatalog {
    static func cask(_ token: String, _ name: String, _ maker: String, _ apps: [String], _ ids: [String] = []) -> AIApp {
        AIApp(id: token, name: name, maker: maker, source: .cask(token), appNames: apps, bundleIDs: ids)
    }
    static func store(_ id: String, _ key: String, _ name: String, _ maker: String, _ apps: [String], _ ids: [String]) -> AIApp {
        AIApp(id: key, name: name, maker: maker, source: .appStore(id), appNames: apps, bundleIDs: ids)
    }

    public static let apps: [AIApp] = [
        cask("chatgpt", "ChatGPT", "OpenAI", ["ChatGPT.app"], ["com.openai.chat", "com.openai.codex"]),
        cask("chatgpt-atlas", "ChatGPT Atlas", "OpenAI", ["ChatGPT Atlas.app"]),
        cask("codex-app", "Codex", "OpenAI", ["Codex.app"]),
        cask("claude", "Claude", "Anthropic", ["Claude.app"], ["com.anthropic.claudefordesktop"]),
        cask("google-gemini", "Gemini", "Google", ["Gemini.app"]),
        store("6670324846", "grok", "Grok", "xAI", ["Grok.app"], ["ai.x.GrokApp"]),
        cask("grok-bot", "Grok Bot", "xAI", ["Grok Bot.app"], ["com.anysphere.sand"]),
        store("6760173601", "muse-meta", "Muse from Meta", "Meta", ["Muse.app", "Muse from Meta.app"], ["com.facebook.hatch"]),
        cask("microsoft-365-copilot", "Microsoft 365 Copilot", "Microsoft", ["Microsoft 365 Copilot.app"]),
        cask("github-copilot-app", "GitHub Copilot", "GitHub", ["GitHub Copilot.app"]),
        cask("perplexity", "Perplexity", "Perplexity", ["Perplexity.app"]),
        cask("comet", "Comet", "Perplexity", ["Comet.app"]),
        cask("thebrowsercompany-dia", "Dia", "The Browser Company", ["Dia.app"]),
        cask("cursor", "Cursor", "Anysphere", ["Cursor.app"]),
        cask("poe", "Poe", "Quora", ["Poe.app"]),
        cask("huggingchat", "HuggingChat", "Hugging Face", ["HuggingChat.app"]),
        cask("ollama-app", "Ollama", "Ollama", ["Ollama.app"]),
        cask("lm-studio", "LM Studio", "LM Studio", ["LM Studio.app"]),
        cask("msty", "Msty", "Msty", ["Msty.app"]),
        cask("jan", "Jan", "Jan", ["Jan.app"]),
        cask("gpt4all", "GPT4All", "Nomic", ["GPT4All.app"]),
        cask("diffusionbee", "Diffusion Bee", "Diffusion Bee", ["DiffusionBee.app"]),
        cask("draw-things", "Draw Things", "Draw Things", ["Draw Things.app"]),
        cask("superwhisper", "Superwhisper", "Superwhisper", ["superwhisper.app", "Superwhisper.app"]),
        cask("macwhisper", "MacWhisper", "Good Snooze", ["MacWhisper.app"]),
        cask("granola", "Granola", "Granola", ["Granola.app"]),
        cask("muse", "Muse", "Muse", ["Muse.app"]),
    ]
}

/// One AI app as it stands on this Mac.
public struct AIAppStatus: Identifiable, Equatable {
    public var app: AIApp
    public var installedPath: String?
    public var installedVersion: String?
    /// Homebrew's newest version, for Homebrew apps.
    public var latestVersion: String?
    public var summary: String?
    public var id: String { app.id }
    public var isInstalled: Bool { installedPath != nil }
    public var needsUpdate: Bool {
        guard let mine = installedVersion, let latest = latestVersion else { return false }
        return SelfUpdater.isNewer(latest, than: mine)
    }
    /// The same app as a row elsewhere in MacSync (for installing and its icon).
    public var missing: MissingApp {
        switch app.source {
        case .cask(let t):
            return MissingApp(app: AppRef(source: .cask, name: t), fromMachines: [],
                              detail: AppDetail(displayName: app.name, summary: summary, bundleID: app.bundleIDs.first))
        case .appStore(let id):
            return MissingApp(app: AppRef(source: .appStore, name: app.name, appStoreID: id), fromMachines: [],
                              detail: AppDetail(displayName: app.name, summary: summary, bundleID: app.bundleIDs.first))
        }
    }
}

extension Engine {
    /// Every well-known AI app, with whether it's here, its version and Homebrew's newest.
    public func aiApps() -> [AIAppStatus] {
        let catalog = CaskCatalog.load(env: env, runner: runner, now: now())
        let fm = FileManager.default
        return AICatalog.apps.compactMap { app -> AIAppStatus? in
            var status = AIAppStatus(app: app)
            if case .cask(let token) = app.source {
                // Not in Homebrew's list (renamed or gone): leave it out rather than offer what can't install.
                if let catalog, catalog.entries[token] == nil { return nil }
                status.latestVersion = catalog?.entries[token]?.version
                status.summary = catalog?.entries[token]?.desc.map { String($0.prefix(120)) }
            }
            var paths = app.appNames.map { env.applicationsDirectory.appendingPathComponent($0).path }
            if env.dockFile == nil { paths += app.bundleIDs.compactMap { locator.path(forBundleID: $0) } }
            if let path = paths.first(where: fm.fileExists) {
                status.installedPath = path
                status.installedVersion = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")?["CFBundleShortVersionString"] as? String
            }
            return status
        }
    }
}
