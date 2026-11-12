// Everything the site says, in one place.

export const links = {
  download: "https://github.com/onlymoein/macsync/releases/latest",
  github: "https://github.com/onlymoein/macsync",
  changelog: "https://github.com/onlymoein/macsync/blob/main/CHANGELOG.md",
  support: "https://buymeacoffee.com/onlymoein",
  raycast: "https://www.raycast.com/onlymoein/macsync",
  liquidglass: "https://github.com/onlymoein/liquidglass",
};

export const brew = "brew tap onlymoein/tap\nbrew trust onlymoein/tap\nbrew install --cask macsync";

export const nav = [
  { id: "features", label: "Features" },
  { id: "options", label: "Options" },
  { id: "inside", label: "Inside" },
  { id: "ai", label: "AI apps" },
  { id: "faq", label: "FAQ" },
];

// The rest, in the phone menu only.
export const navMore = [
  { id: "homebrew", label: "Homebrew" },
  { id: "developers", label: "Developers" },
  { id: "share", label: "Share" },
  { id: "glass", label: "Glass" },
];

export const facts = ["Free and open source", "Signed and notarized by Apple", "Your own iCloud Drive, no account", "macOS 13 or later"];

export const features = [
  { icon: "dock", color: "#0a84ff", title: "One Dock", text: "Add an app to the Dock on one Mac and it's on all of them, in the same order.",
    points: ["Drag to rearrange, click to remove", "Pick which Mac's order wins", "Saved seconds after a change", "Applied when you open the lid, if you like"] },
  { icon: "apps", color: "#5e5ce6", title: "The same apps", text: "Apps on one Mac are offered on the others, one click each or all at once.",
    points: ["Homebrew apps install by themselves", "App Store apps open their page", "Downloaded apps come from the developer", "Every download checked against its checksum"] },
  { icon: "sliders", color: "#30b0c7", title: "The same settings", text: "Trackpad, keyboard, Finder, hot corners and more feel the same everywhere.",
    points: ["Old value shown next to new", "Keep any setting to one Mac", "The settings of apps you pick", "Passwords and keys never read"] },
  { icon: "mug", color: "#ff9f0a", title: "Homebrew, handled", text: "Every Homebrew app and tool stays current on every Mac, like Raycast does it.",
    points: ["Updates install on their own", "A list of what's out of date", "npm and uv tools too", "Open apps are never quit under you"] },
  { icon: "sparkles", color: "#bf5af2", title: "AI apps", text: "Every well-known AI app in one list, installed and kept current on all your Macs.",
    points: ["ChatGPT, Claude, Gemini, Grok and more", "Install on all Macs or this one", "Update All in one click", "Apps you don't have are listed too"] },
  { icon: "doc", color: "#64d2ff", title: "Config files", text: "Your shell, Git, editors and terminals come with you.",
    points: ["zsh, fish, bash, Starship", "VS Code, Cursor, Zed, Neovim, Ghostty", "The fonts you installed", "A file with a key in it stays home"] },
  { icon: "brain", color: "#ff375f", title: "AI setup", text: "Skills, rules and MCP servers for Claude, Codex and Cursor, on every Mac.",
    points: ["CLAUDE.md, AGENTS.md, agents, commands", "MCP servers with keys taken out", "Claude Code plugins", "Checked again for secrets before it leaves"] },
  { icon: "hammer", color: "#32d74b", title: "Developer setup", text: "Xcode and Android Studio set up the way you like them, new in 0.8.14.",
    points: ["Xcode themes, key bindings, snippets", "Simulators each Mac has", "Android SDK platforms and images", "Signing files never leave the Mac"] },
  { icon: "share", color: "#ffd60a", title: "Share my setup", text: "Give a friend your whole setup in one file, with only the parts you choose.",
    points: ["Pick sections with switches", "Send with AirDrop, Messages or Mail", "They pick what to take", "Secrets left out"] },
  { icon: "trash", color: "#ff453a", title: "Remove everywhere", text: "Remove an app from all your Macs at once, or from just this one.",
    points: ["Homebrew uninstalls its apps", "Everything else goes to the Trash", "Each Mac asks before removing", "Bring Back if you change your mind"] },
  { icon: "clock", color: "#8e8e93", title: "Safe by design", text: "Nothing changes until you press Apply, and every Apply can be undone.",
    points: ["Preview everything first", "A restore point before each Apply", "Go back to any of the last 20", "Updates itself while you work"] },
  { icon: "key", color: "#ac8e68", title: "Ready to work", text: "The same apps open at login, extensions are in place, and a list helps you sign in.",
    points: ["Login items", "VS Code and Cursor extensions", "Steam games, through Steam", "A sign-in list, password manager first"] },
];

// Every option a person can change, as MacSync names it.
export const optionGroups = [
  {
    title: "In the menu's Settings",
    note: "The gear at the bottom of the menu bar menu.",
    items: [
      { label: "Sync Automatically", detail: "Saves this Mac's setup to iCloud seconds after a change, and checks the others.", on: true },
      { label: "Apply Dock Changes When I Open the Lid", detail: "Brings the Dock up to date by itself when you sit down at a Mac.", on: true },
      { label: "Update Apps and Tools Automatically", detail: "Homebrew apps, command-line tools, npm and uv, kept current. Off gives you a list instead.", on: true },
      { label: "Update MacSync Automatically", detail: "Installs new versions of MacSync when it's idle, and reopens.", on: true },
      { label: "Open at Login", detail: "Starts MacSync when you log in, in the menu bar.", on: true },
    ],
  },
  {
    title: "Sections of the sync window",
    note: "Each section has an All on switch, and every row has its own.",
    items: [
      { label: "Dock", detail: "Switch off to leave this Mac's Dock alone.", on: true },
      { label: "Apps on your other Macs", detail: "Homebrew apps and apps from their developers.", on: true },
      { label: "App Store apps", detail: "Opens each one's App Store page for you.", on: true },
      { label: "Command-line tools", detail: "Homebrew formulae, like ripgrep or bat.", on: true },
      { label: "App and Homebrew updates", detail: "What's out of date, from → to, with Update All.", on: true },
      { label: "AI apps", detail: "Well-known AI apps, here or not.", on: true },
      { label: "ArtCraft", detail: "Every app in ArtCraft Launcher's catalog.", on: true },
      { label: "Settings", detail: "System settings and the apps you pick.", on: true },
      { label: "Config files", detail: "Shell, Git, editors, terminals, fonts.", on: true },
      { label: "AI setup", detail: "Skills, rules, MCP servers, plugins.", on: true },
      { label: "Developer setup", detail: "Xcode and Android Studio.", on: true },
      { label: "Login items", detail: "Apps that open when you log in.", on: true },
      { label: "Extensions and packages", detail: "VS Code, Cursor, npm, uv, taps, simulators, Android SDK.", on: true },
      { label: "Removed on your other Macs", detail: "Apps you deleted somewhere else.", on: false },
    ],
  },
];

export const dockOrder = [
  { value: "latest", label: "Whoever changed last" },
  { value: "one", label: "One Mac I choose" },
];

export const rowActions = [
  { icon: "power", title: "Not needed here", text: "Switch a row off and this Mac stops offering it. MacSync remembers." },
  { icon: "pin", title: "Keep on this Mac only", text: "A setting, file or login item that stays put, while the rest syncs." },
  { icon: "trash", title: "Remove from this Mac or all", text: "Every Remove asks which. Others ask again before they remove." },
  { icon: "undo", title: "Keep Here and Bring Back", text: "Change your mind about a removal, on any Mac." },
  { icon: "terminal", title: "Install in Terminal", text: "For installers that need your password. MacSync never types it." },
  { icon: "clock", title: "Undo and History", text: "Put this Mac back as it was before any of the last 20 applies." },
];

// The sync window, section by section. `shot` names docs/assets/section-<shot>-<light|dark>.png.
export const sections = [
  { id: "menu", label: "Menu bar", shot: "menu", wide: false, title: "The menu bar menu",
    text: "Click the MacSync icon at the top of your screen.",
    points: ["Each Mac, when it last saved, and which has the latest changes", "Warns when a Mac needs a MacSync update", "Updates for apps, tools and MacSync in one place", "Sync, History, Share, Import, Coffee and Settings along the bottom"] },
  { id: "dock", label: "Dock", shot: "dock", title: "One Dock for all your Macs",
    text: "The combined Dock every Mac will get.",
    points: ["Drag icons to change the order", "Click one, or its ×, to take it off every Dock", "Pick whose order wins", "Changes on another Mac show up live"] },
  { id: "apps", label: "Apps", shot: "apps", title: "Apps on your other Macs",
    text: "Apps another Mac has and this one doesn't.",
    points: ["Each with its icon and what it does", "Homebrew installs; the rest download from the developer", "Get All, or one at a time", "Installers that need a password open in Terminal"] },
  { id: "appStore", label: "App Store", shot: "appStore", title: "App Store apps",
    text: "Listed apart, because only the App Store can install them.",
    points: ["Open in App Store goes straight to the app", "Click Get there", "Switch one off and it isn't offered again"] },
  { id: "tools", label: "Tools", shot: "tools", title: "Command-line tools",
    text: "Homebrew packages, like ripgrep or bat.",
    points: ["Install All in one go, or one by one", "Dependencies are never offered on their own", "Remove a tool from every Mac"] },
  { id: "updates", label: "Updates", shot: "updates", title: "App and Homebrew updates",
    text: "What's out of date on this Mac, and what was just updated.",
    points: ["From → to for each app and tool", "Update or Update All", "Open apps wait, with Quit and Update", "Self-updating apps like ChatGPT stay current too"] },
  { id: "aiApps", label: "AI apps", shot: "ai-apps", title: "AI apps",
    text: "Every well-known AI app, whether or not you have it yet.",
    points: ["Install on All Macs, or This Mac Only", "Your version next to the newest", "Update All", "The ones you don't have fold away"] },
  { id: "artcraft", label: "ArtCraft", shot: "artcraft", title: "ArtCraft",
    text: "Every app in ArtCraft Launcher's catalog.",
    points: ["Install All, Update All or Remove All", "Checked against checksums and the signature", "Installed in the launcher's folder", "A bar with each step and its percent"] },
  { id: "toRemove", label: "Removed", shot: "toRemove", title: "Removed on your other Macs",
    text: "Apps you deleted somewhere else.",
    points: ["Uninstall here, or Keep Here", "Homebrew uninstalls; the rest go to the Trash", "Nothing is lost"] },
  { id: "settings", label: "Settings", shot: "settings", title: "Settings",
    text: "Trackpad, keyboard, Finder, Dock, appearance, screenshots and more.",
    points: ["Old value next to new", "Hot corners, gestures, input sources, shortcuts", "Switch off any one to keep it here", "Nothing changes until Apply"] },
  { id: "config", label: "Config files", shot: "config", title: "Config files",
    text: "Shell, Git, editors, terminals, Raycast and fonts.",
    points: ["The lines that change, before you apply", "Your own newer edits are never replaced", "A file with a secret stays on its Mac", "Remove from this Mac or all of them"] },
  { id: "aiSetup", label: "AI setup", shot: "ai", title: "AI setup",
    text: "Claude Code, Codex, Cursor and the Claude app.",
    points: ["Skills, agents, commands and rules", "MCP servers, keys taken out", "Claude Code plugins from their marketplace", "Each Mac keeps its own keys"] },
  { id: "signin", label: "Sign in", shot: "signin", title: "Sign in to new apps",
    text: "After apps install, the ones that need an account.",
    points: ["Your password manager first", "A hint for each app", "Open, sign in, Done", "MacSync never types a password"] },
  { id: "share", label: "Share", shot: "share", title: "Share My Setup",
    text: "Choose sections, save one file, send it.",
    points: ["A switch for each section, and the file's size", "Login items start off", "Your friend clicks Import, or double-clicks the file", "Remove it any time"] },
  { id: "history", label: "History", shot: "history", title: "History",
    text: "A restore point for every Apply.",
    points: ["This Mac's Dock and settings saved first", "Restore any point, not just the last", "The last 20 are kept"] },
];

export const homebrewPoints = [
  "Install something with Homebrew on one Mac and the others offer it",
  "Each Mac checks when MacSync opens and every six hours",
  "Apps, command-line tools, and apps that update themselves",
  "npm global packages and uv tools are kept current too",
  "An open app is never quit under you: it waits, with Quit and Update",
  "Rather choose? Turn automatic off and get a list, with Update All",
  "Uninstall on one Mac and the others offer to remove it, or keep it",
];

export const outdatedDemo = [
  { name: "Visual Studio Code", from: "1.105.0", to: "1.106.1", kind: "App" },
  { name: "ffmpeg", from: "8.0", to: "8.0.1", kind: "Tool" },
  { name: "vercel", from: "48.2.0", to: "48.4.1", kind: "npm" },
  { name: "Raycast", from: "1.103.2", to: "1.104.0", kind: "App" },
];

export const aiApps = [
  ["ChatGPT", "OpenAI"], ["Claude", "Anthropic"], ["Gemini", "Google"], ["Grok", "xAI"], ["Muse from Meta", "Meta"],
  ["Codex", "OpenAI"], ["ChatGPT Atlas", "OpenAI"], ["Microsoft 365 Copilot", "Microsoft"], ["GitHub Copilot", "GitHub"],
  ["Perplexity", "Perplexity"], ["Comet", "Perplexity"], ["Dia", "The Browser Company"], ["Cursor", "Anysphere"],
  ["Grok Bot", "xAI"], ["Poe", "Quora"], ["HuggingChat", "Hugging Face"], ["Ollama", "Ollama"], ["LM Studio", "LM Studio"],
  ["Msty", "Msty"], ["Jan", "Jan"], ["GPT4All", "Nomic"], ["Diffusion Bee", "Diffusion Bee"], ["Draw Things", "Draw Things"],
  ["Superwhisper", "Superwhisper"], ["MacWhisper", "Good Snooze"], ["Granola", "Granola"], ["Muse", "Muse"],
];

export const shareSections = [
  { label: "Apps", detail: "Homebrew apps and apps from their developers", on: true },
  { label: "App Store apps", detail: "Opens each one's App Store page", on: true },
  { label: "Command-line tools", detail: "Homebrew command-line tools and taps", on: true },
  { label: "Extensions, plugins and packages", detail: "VS Code and Cursor extensions, npm, uv, Claude Code plugins", on: true },
  { label: "Settings", detail: "Trackpad, keyboard, Finder, Dock behaviour, hot corners", on: true },
  { label: "Config files", detail: "Shell, Git, editors, terminals (fonts stay with you)", on: true },
  { label: "AI setup", detail: "Skills, rules, CLAUDE.md, MCP servers, with keys taken out", on: true },
  { label: "Login items", detail: "Apps that open at login", on: false },
];

export const developer = [
  { icon: "hammer", title: "Xcode", syncs: ["Color themes", "Key bindings", "Code snippets", "File and project templates", "The simulators each Mac has, with Get for the missing ones"],
    never: "Provisioning profiles and signing certificates" },
  { icon: "android", title: "Android Studio", syncs: ["Keymaps", "Code styles", "Color schemes", "Live templates and file templates", "SDK platforms, build tools and system images, through Google's sdkmanager"],
    never: "adb keys and keystores. Licenses are never accepted for you" },
];

export const craftApps = ["photocraft", "vectorcraft", "pdfcraft", "wordcraft", "gridcraft", "deckcraft", "designcraft", "filmcraft", "effectcraft",
  "lightcraft", "anicraft", "cadcraft", "solidcraft", "soundcraft", "texturecraft", "materialcraft", "mailcraft", "figcraft", "craft-anything"];

export const steps = [
  { title: "Each Mac saves its setup", points: ["A small file per Mac in your iCloud Drive", "Dock, apps, chosen settings and files", "Updated seconds after a change"] },
  { title: "The others see what's new", points: ["Apps to add, Dock changes, settings", "All in one window, grouped", "The menu bar icon tells you"] },
  { title: "You press Apply", points: ["A restore point is saved first", "Undo in one click", "Or go back to any of the last 20"] },
];

export const kept = ["Dock apps, order, icon size and position", "Apps from Homebrew, the App Store and developers", "Command-line tools, npm and uv tools",
  "System settings and the app settings you pick", "Hot corners, input sources, shortcuts, gestures", "Config files, fonts, AI skills and rules, MCP servers",
  "Login items, extensions, Claude Code plugins", "Xcode and Android Studio setup, simulators, SDK packages"];
export const never = ["Passwords, tokens, API keys and license keys", "SSH and GPG keys, ~/.aws, shell history, .env files",
  "Provisioning profiles, keystores, adb keys", "Window positions and per-Mac details", "Your documents, photos and projects",
  "The apps themselves: they come from where they're published"];

export const raycast = ["Open Sync Window", "Sync Now", "Apply Dock Layout", "Undo", "Show Status", "Show History",
  "Check Homebrew Updates", "Update Homebrew Apps", "Share My Setup"];

export const cli = `# each Mac and whether it's in sync
macsync status
# what applying would change, then apply it
macsync preview
macsync apply
# go back
macsync undo
macsync restore-points
# Homebrew: what's out of date, then update it all
macsync outdated
macsync upgrade
# what this Mac shares, and what it keeps back
macsync files`;

export const faq = [
  ["macOS says it can't verify MacSync", "That happens for a little while after a release, while Apple finishes checking it. Open System Settings → Privacy & Security and click Open Anyway, then open MacSync again."],
  ["Do I need an account or a server?", "No. MacSync only uses your own iCloud Drive. Turn on iCloud Drive on each Mac, signed in to the same Apple Account."],
  ["Will it delete my apps?", "Only when you ask. Remove from All Macs uninstalls an app after you confirm, and each other Mac asks before removing it there. Homebrew uninstalls its own apps; anything else goes to the Trash."],
  ["Why does an app say Install in Terminal?", "Some installers, like Docker Desktop or Adobe's, need your Mac password. MacSync never types a password, so it opens Terminal with the install ready and you type it there. Several at once share one window."],
  ["How does it install apps I downloaded myself?", "It finds where the app is published, through Homebrew's public list or the app's own update feed, downloads it from there, checks it, and installs it or opens the installer."],
  ["Does it sync Xcode and Android Studio?", "Their settings, themes, key bindings and templates, plus the simulators and Android SDK packages each Mac has. Never provisioning profiles, keystores or adb keys, and Android licenses are never accepted for you."],
  ["Does it work with ArtCraft Launcher?", "Yes. Craft apps install into the launcher's folder and are recorded in its list, so the launcher shows them and keeps them updated."],
  ["What if I don't like a change?", "Press Undo in the menu, or open History and restore any of the last 20 applies. Installed apps stay installed."],
  ["How does it stay up to date?", "MacSync checks for a new version when you open its menu and every ten minutes, and installs it once it isn't busy. Turn that off in Settings, or click Check in the menu."],
  ["Is it open source?", "Yes, under the MIT license. The code is on GitHub, and this page's glass is liquidglass, from the same GitHub."],
];
