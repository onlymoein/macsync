// Pages that answer one question each. Plain facts; every claim here is something MacSync does.
// body: [heading, paragraph or list of steps]
export const guides = [
  { slug: "sync-dock-between-macs", title: "How to sync the Dock between Macs",
    description: "Keep the same Dock, in the same order, on every Mac you own.",
    answer: "macOS has no built-in Dock sync. Install MacSync, a free menu bar app, on each Mac with iCloud Drive on and the same Apple Account. A Dock change on one Mac is saved within seconds, and the others take the same apps in the same order when you open the lid or press Apply.",
    body: [
      ["Step by step", ["Turn on iCloud Drive on both Macs, signed in to the same Apple Account.", "Install MacSync on both and let it open at login.", "Arrange the Dock on one Mac.", "On the other, open the lid, or click MacSync in the menu bar, Review Changes and Apply."]],
      ["What comes across", "The apps and their order, icon size, the Dock's position, and Safari web apps. An app a Mac doesn't have is skipped there and offered to install, so you never get a question mark in the Dock."],
      ["Keeping one Mac different", "Switch the Dock section off on that Mac. You can also choose whether the last change wins or one Mac always does."],
      ["Undoing it", "A restore point is saved before every Apply. Undo goes back one; History goes back to any of the last 20."],
    ] },
  { slug: "sync-apps-between-macs", title: "How to install the same apps on all your Macs",
    description: "See what your other Macs have and install it, without keeping a list.",
    answer: "Install MacSync on each Mac. It lists the apps your other Macs have and this one doesn't, and installs them: Homebrew apps in one click, App Store apps from their page, and others from their developer.",
    body: [
      ["Step by step", ["Install MacSync on each Mac, with iCloud Drive on.", "Open the sync window and look at Apps on your other Macs.", "Press Get on one app, or Get All.", "Switch off any app a Mac doesn't need; MacSync remembers."]],
      ["Where the apps come from", "Never from your other Mac. Homebrew installs its own, the App Store its own, and the rest are downloaded from where their developer publishes them and checked against their checksum or signature."],
      ["Keeping them up to date", "MacSync updates Homebrew apps and tools, npm and uv packages, and apps that update themselves. An app you have open is updated after you quit it."],
      ["Removing an app everywhere", "Remove from All Macs uninstalls it here, and each other Mac asks before removing its own copy."],
    ] },
  { slug: "sync-mac-settings", title: "How to sync Mac settings between two computers",
    description: "The same trackpad, keyboard, Finder and app settings on each Mac.",
    answer: "MacSync copies the macOS settings you choose (trackpad, keyboard, Finder, Dock behaviour, hot corners, screenshots and more) between your Macs through your own iCloud Drive. Each change shows the old value next to the new one, and nothing changes until you press Apply.",
    body: [
      ["Step by step", ["Install MacSync on both Macs.", "Change a setting on one Mac as usual, in System Settings.", "On the other, open Settings in the sync window and compare old and new.", "Switch off anything that should stay different, and press Apply."]],
      ["What never syncs", "Passwords, tokens, API keys, license keys, SSH and GPG keys, shell history and .env files. A config file with a key in it stays on its Mac."],
      ["Good to know", "Some trackpad, keyboard and appearance settings need you to log out once before they take full effect."],
    ] },
  { slug: "set-up-new-mac", title: "How to set up a new Mac like your old one",
    description: "A clean install with your Dock, apps, settings and dotfiles, without Migration Assistant.",
    answer: "Migration Assistant copies everything once, including what you'd rather leave behind. To start clean and still get your setup, install MacSync on the old Mac, let it save, then install it on the new one and press Apply: it brings the Dock, apps, settings, config files and developer setup, and keeps both Macs the same afterwards.",
    body: [
      ["Step by step", ["On the old Mac, install MacSync and let it sync.", "On the new Mac, sign in to the same Apple Account and turn on iCloud Drive.", "Install MacSync and open Review Changes.", "Choose what you want and press Apply, then work through the sign-in list."]],
      ["MacSync or Migration Assistant?", "Migration Assistant moves accounts, documents and apps from one Mac to another, once. MacSync doesn't move documents; it keeps the setup of Macs you go on using the same."],
      ["MacSync or a Brewfile?", "brew bundle installs what a file you maintain says. MacSync works out the list from what each Mac has, and also covers App Store and downloaded apps, the Dock, settings and config files."],
    ] },
  { slug: "sync-dotfiles-ai-tools-macs", title: "How to sync dotfiles and AI tool setup across Macs",
    description: "Shell, Git, editors, Claude, Codex and Cursor the same on each Mac, with keys left out.",
    answer: "MacSync syncs config files (zsh, fish, bash, Git, VS Code, Cursor, Zed, Neovim, Ghostty) and AI setup (CLAUDE.md, AGENTS.md, skills, agents, rules and MCP servers) through your own iCloud Drive. Keys are taken out of MCP servers, and a config file containing a secret stays on its Mac.",
    body: [
      ["Step by step", ["Install MacSync on each Mac.", "Open Config files and AI setup in the sync window.", "Read the lines that would change.", "Press Apply, then add each Mac's own keys where MCP servers need them."]],
      ["Do I need a dotfiles repo?", "No. There's no Git repository and no symlinks: MacSync reads the files where they are, and never replaces a newer edit of yours."],
      ["Editors and packages", "VS Code and Cursor extensions, npm global packages, uv tools, Homebrew taps and Claude Code plugins are offered on the Macs that lack them."],
    ] },
];
