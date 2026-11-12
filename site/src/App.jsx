import { useEffect, useState } from "react";
import { Button, Glass, GlassGroup, Input, Menu, Progress, SegmentedControl, Slider, Switch } from "@onlymoein/liquidglass";
import { Icon } from "./icons.jsx";
import * as c from "./content.js";

const asset = (name) => `assets/${name}`;

/** A screenshot in both appearances; CSS shows the one that matches the page. */
function Shot({ name, alt, className = "", eager = false }) {
  return (
    <span className={`shot ${className}`}>
      <img className="shot-light" src={asset(`${name}-light.png`)} alt={alt} loading={eager ? "eager" : "lazy"} decoding="async" />
      <img className="shot-dark" src={asset(`${name}-dark.png`)} alt="" aria-hidden="true" loading={eager ? "eager" : "lazy"} decoding="async" />
    </span>
  );
}

function Section({ id, eyebrow, title, lead, children, className = "" }) {
  return (
    <section id={id} className={`section ${className}`}>
      <header className="section-head">
        {eyebrow && <p className="eyebrow">{eyebrow}</p>}
        <h2>{title}</h2>
        {lead && <p className="lead">{lead}</p>}
      </header>
      {children}
    </section>
  );
}

function Tile({ icon, color, size = 44 }) {
  return (
    <span className="tile" style={{ "--tile": color, width: size, height: size }}>
      <Icon name={icon} size={Math.round(size * 0.52)} stroke={1.9} />
    </span>
  );
}

function Checks({ items, kind = "check" }) {
  return (
    <ul className={`checks checks-${kind}`}>
      {items.map((item) => (
        <li key={item}><Icon name={kind === "never" ? "x" : "check"} size={16} stroke={2.2} /><span>{item}</span></li>
      ))}
    </ul>
  );
}

// MARK: Navigation

function useTheme() {
  const [theme, setTheme] = useState("auto");
  useEffect(() => {
    try { setTheme(localStorage.getItem("macsync.theme") || "auto"); } catch {}
  }, []);
  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const resolved = theme === "auto" ? (media.matches ? "dark" : "light") : theme;
      document.documentElement.dataset.theme = resolved;
    };
    apply();
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [theme]);
  const choose = (value) => {
    setTheme(value);
    try { localStorage.setItem("macsync.theme", value); } catch {}
  };
  return [theme, choose];
}

function Nav() {
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);
  return (
    <div className={`nav-wrap ${scrolled ? "is-scrolled" : ""}`}>
      <Glass className="nav">
        <a className="brand" href="#top" aria-label="MacSync, back to the top">
          <img src={asset("icon.png")} alt="" width="30" height="30" />
          <span>MacSync</span>
        </a>
        <nav className="nav-links" aria-label="Sections">
          {c.nav.map((item) => <a key={item.id} href={`#${item.id}`}>{item.label}</a>)}
        </nav>
        <div className="nav-actions">
          <a className="nav-icon" href={c.links.github} aria-label="MacSync on GitHub"><Icon name="github" size={20} /></a>
          <Button className="nav-coffee" icon={<Icon name="coffee" size={17} />} onClick={() => window.open(c.links.support, "_blank", "noopener")}>
            Support
          </Button>
          <Button variant="filled" icon={<Icon name="download" size={17} />} onClick={() => { location.href = c.links.download; }}>
            Download
          </Button>
          <Menu
            className="nav-menu"
            aria-label="Sections"
            icon={<Icon name="menu" size={18} />}
            align="end"
            chevron={false}
            items={[...c.nav.map((item) => ({ label: item.label, href: `#${item.id}` })), "separator",
              { label: "Buy me a coffee", href: c.links.support }, { label: "GitHub", href: c.links.github }]}
          />
        </div>
      </Glass>
    </div>
  );
}

// MARK: Hero

function CopyCommand() {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try { await navigator.clipboard.writeText(c.brew); setCopied(true); setTimeout(() => setCopied(false), 1800); } catch {}
  };
  return (
    <Glass className="command">
      <pre><code>{c.brew}</code></pre>
      <Button size="small" icon={<Icon name={copied ? "check" : "copy"} size={15} />} onClick={copy} aria-label="Copy the Homebrew command">
        {copied ? "Copied" : "Copy"}
      </Button>
    </Glass>
  );
}

function Hero() {
  return (
    <section className="hero" id="top">
      <div className="hero-copy">
        <a className="pill-link" href="#developers">
          <Glass className="pill"><span className="pill-dot" />New in 0.8.14: Developer setup and a fresh menu <span aria-hidden="true">→</span></Glass>
        </a>
        <h1>Every Mac,<br /><span className="grad">set up the same.</span></h1>
        <p className="hero-lead">
          One Dock, the same apps, the same settings, files and AI setup on every Mac you use.
          Through your own iCloud Drive, with nothing changed until you press Apply.
        </p>
        <div className="hero-cta">
          <Button variant="filled" size="large" icon={<Icon name="download" size={20} />} onClick={() => { location.href = c.links.download; }}>
            Download MacSync
          </Button>
          <Button size="large" icon={<Icon name="coffee" size={20} />} onClick={() => window.open(c.links.support, "_blank", "noopener")}>
            Buy me a coffee
          </Button>
        </div>
        <CopyCommand />
        <ul className="facts">
          {c.facts.map((fact) => <li key={fact}><Icon name="check" size={15} stroke={2.4} />{fact}</li>)}
        </ul>
      </div>
      <div className="hero-art">
        <Glass className="frame frame-window"><Shot name="window" alt="The MacSync sync window, with the Dock, apps and settings from your other Macs." eager /></Glass>
        <Glass className="frame frame-menu"><Shot name="menu" alt="The MacSync menu: your Macs, updates, and Sync, History, Share, Import, Coffee and Settings." eager /></Glass>
      </div>
    </section>
  );
}

// MARK: Features

function Features() {
  return (
    <Section id="features" eyebrow="Features" title="Everything that makes a Mac yours"
      lead="Each part has its own section in the sync window, with a switch for the whole section and one for every item.">
      <div className="bento">
        {c.features.map((f, i) => (
          <Glass key={f.title} className={`card feature ${i < 2 ? "feature-big" : ""}`}>
            <Tile icon={f.icon} color={f.color} />
            <h3>{f.title}</h3>
            <p>{f.text}</p>
            <Checks items={f.points} />
          </Glass>
        ))}
      </div>
    </Section>
  );
}

// MARK: Options

function Options() {
  const [values, setValues] = useState(() =>
    Object.fromEntries(c.optionGroups.flatMap((g) => g.items.map((item) => [item.label, item.on]))));
  const [order, setOrder] = useState("latest");
  const set = (label, on) => setValues((v) => ({ ...v, [label]: on }));
  return (
    <Section id="options" eyebrow="Every option" title="You decide what syncs"
      lead="These are all of MacSync's options. Try the switches: they're the same ones you'll find in the app, and nothing here touches your Mac.">
      <div className="options">
        {c.optionGroups.map((group) => (
          <Glass key={group.title} className="card option-group">
            <h3>{group.title}</h3>
            <p className="muted">{group.note}</p>
            <ul className="option-list">
              {group.items.map((item) => (
                <li key={item.label}>
                  <div>
                    <strong>{item.label}</strong>
                    <span>{item.detail}</span>
                  </div>
                  <Switch aria-label={item.label} checked={values[item.label]} onCheckedChange={(on) => set(item.label, on)} />
                </li>
              ))}
              {group.title.startsWith("In the menu") && (
                <li className="option-order">
                  <div>
                    <strong>Dock order</strong>
                    <span>{order === "latest" ? "Every Mac takes the order of the Mac that changed its Dock last." : "Every Mac keeps the order of one Mac you pick, in the Dock section."}</span>
                  </div>
                  <SegmentedControl aria-label="Dock order" items={c.dockOrder} value={order} onValueChange={setOrder} />
                </li>
              )}
            </ul>
          </Glass>
        ))}
        <Glass className="card option-group">
          <h3>On every row</h3>
          <p className="muted">What you can do with any app, setting, file or login item.</p>
          <ul className="row-actions">
            {c.rowActions.map((a) => (
              <li key={a.title}><span className="mini-tile"><Icon name={a.icon} size={18} /></span><div><strong>{a.title}</strong><span>{a.text}</span></div></li>
            ))}
          </ul>
        </Glass>
      </div>
    </Section>
  );
}

// MARK: Inside the app

function Inside() {
  const [current, setCurrent] = useState(c.sections[0].id);
  const section = c.sections.find((s) => s.id === current);
  const shot = section.shot === "menu" ? "menu" : `section-${section.shot}`;
  return (
    <Section id="inside" eyebrow="Inside the app" title="The sync window, section by section"
      lead="Every section folds open and shut. Your choices wait at the bottom until you press Apply.">
      <div className="tabs" role="tablist" aria-label="Sections of the sync window">
        <GlassGroup spacing={8} className="tab-group">
          {c.sections.map((s) => (
            <Button key={s.id} role="tab" aria-selected={s.id === current} size="small"
              variant={s.id === current ? "filled" : "glass"} onClick={() => setCurrent(s.id)}>
              {s.label}
            </Button>
          ))}
        </GlassGroup>
      </div>
      <Glass className="card inside" role="tabpanel" aria-label={section.title}>
        <div className="inside-text">
          <h3>{section.title}</h3>
          <p>{section.text}</p>
          <Checks items={section.points} />
        </div>
        <div className={`inside-shot ${section.shot === "menu" ? "is-menu" : ""}`}>
          <Shot key={shot} name={shot} alt={`${section.title} in MacSync.`} />
        </div>
      </Glass>
    </Section>
  );
}

// MARK: Homebrew

function Homebrew() {
  const [done, setDone] = useState(-1);
  const running = done >= 0 && done < c.outdatedDemo.length;
  useEffect(() => {
    if (!running) return;
    const t = setTimeout(() => setDone((d) => d + 1), 900);
    return () => clearTimeout(t);
  }, [done, running]);
  const finished = done >= c.outdatedDemo.length;
  return (
    <Section id="homebrew" eyebrow="Homebrew, handled" title="Every app and tool, up to date on every Mac"
      lead="MacSync keeps Homebrew apps and command-line tools current, the way Raycast does, and tells you what changed.">
      <div className="split">
        <Checks items={c.homebrewPoints} />
        <Glass className="card demo">
          <div className="demo-head">
            <Tile icon="mug" color="#ff9f0a" size={38} />
            <div>
              <strong>{finished ? "Apps and tools are up to date" : `${c.outdatedDemo.length - Math.max(done, 0)} updates for apps and tools`}</strong>
              <span className="muted">{running ? `Updating ${c.outdatedDemo[done].name}…` : finished ? "Updated 4 with Homebrew" : "Checked just now"}</span>
            </div>
            {finished
              ? <Button size="small" onClick={() => setDone(-1)}>Again</Button>
              : <Button size="small" variant="filled" disabled={running} onClick={() => setDone(0)}>Update All</Button>}
          </div>
          <Progress value={finished ? 1 : Math.max(done, 0) / c.outdatedDemo.length} aria-label="Update progress" />
          <ul className="outdated">
            {c.outdatedDemo.map((item, i) => (
              <li key={item.name} className={i < done || finished ? "is-done" : i === done ? "is-now" : ""}>
                <span className="kind">{item.kind}</span>
                <strong>{item.name}</strong>
                <span className="muted ver">{item.from} → {item.to}</span>
                <span className="state">{i < done || finished ? <Icon name="check" size={16} stroke={2.4} /> : i === done ? "Updating" : "Waiting"}</span>
              </li>
            ))}
          </ul>
        </Glass>
      </div>
    </Section>
  );
}

// MARK: AI apps

function hue(name) {
  let h = 0;
  for (const ch of name) h = (h * 31 + ch.charCodeAt(0)) % 360;
  return h;
}

function AIApps() {
  const [where, setWhere] = useState("all");
  return (
    <Section id="ai" eyebrow="AI apps" title="Every well-known AI app, on all your Macs"
      lead="One list of the AI apps people use, whether you have them yet or not. Install one or all, and Update All when a newer one is out.">
      <div className="ai-bar">
        <SegmentedControl aria-label="Where to install" value={where} onValueChange={setWhere}
          items={[{ value: "all", label: "Install on All Macs" }, { value: "here", label: "This Mac Only" }]} />
        <span className="muted">{where === "all" ? "Each of your Macs installs it, and keeps it current." : "Only this Mac gets it; the others leave it switched off."}</span>
      </div>
      <GlassGroup spacing={6} className="ai-grid">
        {c.aiApps.map(([name, maker]) => (
          <Glass key={name} className="ai-app">
            <span className="ai-avatar" style={{ "--h": hue(name) }}>{name[0]}</span>
            <span><strong>{name}</strong><small>{maker}</small></span>
          </Glass>
        ))}
      </GlassGroup>
      <p className="note">Homebrew installs most of them. Grok and Muse from Meta open their App Store page. Apps that update themselves, like ChatGPT and Claude, are handed to Homebrew so they stay current too.</p>
    </Section>
  );
}

// MARK: Developers

function Developers() {
  return (
    <Section id="developers" eyebrow="New in 0.8.14" title="Your developer setup, on every Mac"
      lead="Xcode and Android Studio feel like home on any Mac: the same themes, keys and templates, and the same simulators and SDKs ready to install.">
      <div className="dev">
        {c.developer.map((d) => (
          <Glass key={d.title} className="card dev-card">
            <Tile icon={d.icon} color={d.icon === "android" ? "#3ddc84" : "#147efb"} size={52} />
            <h3>{d.title}</h3>
            <Checks items={d.syncs} />
            <p className="never-line"><Icon name="lock" size={15} /> Never copied: {d.never}.</p>
          </Glass>
        ))}
      </div>
    </Section>
  );
}

// MARK: Share

function Share() {
  const [name, setName] = useState("Mehdi");
  const [on, setOn] = useState(() => Object.fromEntries(c.shareSections.map((s) => [s.label, s.on])));
  const [made, setMade] = useState(false);
  const count = Object.values(on).filter(Boolean).length;
  const mb = (0.4 + (on["AI setup"] ? 3.4 : 0) + (on["Config files"] ? 0.2 : 0)).toFixed(1);
  return (
    <Section id="share" eyebrow="Share my setup" title="Give a friend your whole setup in one file"
      lead="Choose the sections, save the file, and send it with AirDrop, Messages or Mail. Your friend double-clicks it and picks what to take.">
      <div className="split">
        <div className="share-copy">
          <Checks items={[
            "A switch for each section; login items start off",
            "They see it in MacSync as “Your name's setup”",
            "Apps download from where they're published, never from you",
            "The file is compressed, usually a few megabytes",
            "To open it: double-click the file, or click Import in MacSync",
            "Remove it any time; what they already took stays",
          ]} />
          <p className="never-line"><Icon name="lock" size={15} /> Never in it: passwords, keys, tokens or any file with one, your fonts, app data, your Dock or your history.</p>
        </div>
        <Glass className="card sheet">
          <div className="sheet-head">
            <Tile icon="share" color="#0a84ff" size={40} />
            <div><strong>Share your setup</strong><span className="muted">They'll see "{name.trim() || "A friend"}'s setup"</span></div>
          </div>
          <Input aria-label="Your name" value={name} onValueChange={setName} placeholder="Your name" />
          <ul className="option-list compact">
            {c.shareSections.map((s) => (
              <li key={s.label}>
                <div><strong>{s.label}</strong><span>{s.detail}</span></div>
                <Switch aria-label={s.label} checked={on[s.label]} onCheckedChange={(v) => { setOn((o) => ({ ...o, [s.label]: v })); setMade(false); }} />
              </li>
            ))}
          </ul>
          <div className="sheet-foot">
            <span className="muted">{made ? `Saved "${name.trim() || "My"}'s MacSync setup.macsync"` : count ? `About ${mb} MB` : "Choose at least one section"}</span>
            <Button variant="filled" disabled={!count} onClick={() => setMade(true)}>Share…</Button>
          </div>
        </Glass>
      </div>
    </Section>
  );
}

// MARK: Progress

const queue = ["Ghostty", "Raycast", "btop", "ripgrep", "PhotoCraft"];

function Progressing() {
  const [step, setStep] = useState(1);
  const [pct, setPct] = useState(42);
  useEffect(() => {
    const t = setInterval(() => {
      setPct((p) => {
        if (p >= 100) { setStep((s) => (s + 1) % queue.length); return 0; }
        return Math.min(100, p + 7);
      });
    }, 260);
    return () => clearInterval(t);
  }, []);
  return (
    <Section id="progress" eyebrow="Always shows its work" title="See exactly what it's doing, and what's next"
      lead="A bar while it installs, removes or updates: how many are done, what's happening now, and what comes next. In the window and in the menu bar.">
      <Glass className="card progress-card">
        <div className="progress-line">
          <strong>Getting apps: {step + 1} of {queue.length}</strong>
          <span className="muted">{queue[step]}{queue[step + 1] ? ` · next: ${queue[step + 1]}` : ""}</span>
        </div>
        <Progress value={(step + pct / 100) / queue.length} aria-label="All apps" />
        <ul className="queue">
          {queue.map((name, i) => (
            <li key={name}>
              <span>{name}</span>
              {i < step ? <span className="ok"><Icon name="check" size={15} stroke={2.4} /> Installed</span>
                : i === step ? <span className="now"><Progress value={pct / 100} aria-label={name} /><small>Downloading {pct}%</small></span>
                : <span className="muted">Waiting</span>}
            </li>
          ))}
        </ul>
      </Glass>
    </Section>
  );
}

// MARK: ArtCraft

function ArtCraft() {
  const label = (id) => id === "craft-anything" ? "Craft Anything" : id.replace("craft", "").replace(/^./, (x) => x.toUpperCase()) + "Craft";
  return (
    <Section id="artcraft" eyebrow="ArtCraft" title="The whole ArtCraft suite, on every Mac"
      lead="MacSync reads ArtCraft Launcher's own catalog, so every Craft app is there, and new ones appear as ArtCraft adds them.">
      <GlassGroup spacing={8} className="craft-grid">
        {c.craftApps.map((id) => (
          <Glass key={id} className="craft">
            <img src={asset(`artcraft/${id}.png`)} alt="" width="48" height="48" loading="lazy" />
            <span>{label(id)}</span>
          </Glass>
        ))}
      </GlassGroup>
      <div className="craft-points">
        <Checks items={["Install All, Update All, or one at a time", "Remove from all Macs, or this one", "Checked against published checksums and the signature", "Installed in the launcher's own folder and recorded in its list"]} />
      </div>
    </Section>
  );
}

// MARK: How it works, privacy, keyboard

function How() {
  return (
    <Section id="how" eyebrow="How it works" title="Three steps, all on your Macs">
      <ol className="steps">
        {c.steps.map((s, i) => (
          <li key={s.title}>
            <Glass className="card step">
              <span className="step-n">{i + 1}</span>
              <h3>{s.title}</h3>
              <Checks items={s.points} />
            </Glass>
          </li>
        ))}
      </ol>
    </Section>
  );
}

function Privacy() {
  return (
    <Section id="privacy" eyebrow="Privacy" title="What syncs, and what never does"
      lead="Everything lives in your own iCloud Drive. There's no server and no account.">
      <div className="privacy">
        <Glass className="card"><h3><Icon name="sync" /> Kept the same</h3><Checks items={c.kept} /></Glass>
        <Glass className="card"><h3><Icon name="shield" /> Never copied</h3><Checks items={c.never} kind="never" /></Glass>
      </div>
    </Section>
  );
}

function Keyboard() {
  return (
    <Section id="keyboard" eyebrow="Keyboard" title="Raycast and Terminal too">
      <div className="split">
        <Glass className="card">
          <h3><Icon name="raycast" /> Raycast commands</h3>
          <div className="chips">{c.raycast.map((r) => <span key={r} className="chip">{r}</span>)}</div>
          <p className="muted">And <code>macsync://</code> links open the window, History or Share.</p>
        </Glass>
        <Glass className="card code"><h3><Icon name="terminal" /> The macsync command</h3><pre><code>{c.cli}</code></pre></Glass>
      </div>
    </Section>
  );
}

function Faq() {
  return (
    <Section id="faq" eyebrow="Questions" title="Good to know">
      <div className="faq">
        {c.faq.map(([q, a]) => (
          <Glass key={q} className="card faq-item">
            <details>
              <summary>{q}<span className="chev" aria-hidden="true" /></summary>
              <p>{a}</p>
            </details>
          </Glass>
        ))}
      </div>
    </Section>
  );
}

// MARK: The glass on this page

const glassLooks = [
  { value: "tinted", label: "Tinted", amount: 0 },
  { value: "regular", label: "Regular", amount: 0.55 },
  { value: "clear", label: "Clear", amount: 1 },
];

function GlassCredit() {
  const [amount, setAmount] = useState(0.55);
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    try { const saved = parseFloat(localStorage.getItem("macsync.glass")); if (!Number.isNaN(saved)) setAmount(saved); } catch {}
  }, []);
  useEffect(() => {
    document.documentElement.style.setProperty("--lg-transparency", String(amount));
    try { localStorage.setItem("macsync.glass", String(amount)); } catch {}
  }, [amount]);
  const look = amount < 0.25 ? "tinted" : amount > 0.8 ? "clear" : "regular";
  const install = "npm install @onlymoein/liquidglass";
  const copy = async () => {
    try { await navigator.clipboard.writeText(install); setCopied(true); setTimeout(() => setCopied(false), 1800); } catch {}
  };
  return (
    <Section id="glass" eyebrow="The glass on this page" title="Made with liquidglass"
      lead="Every piece of glass here, from the bar at the top to the switches, is liquidglass: Liquid Glass for the web that bends the light behind it, from the same GitHub as MacSync. It's free and open source, so you can use it too.">
      <div className="split">
        <Glass className="card glass-tuner">
          <h3><Icon name="sliders" /> Tune the glass</h3>
          <p className="muted">Like the setting on iPhone. It changes the whole page, and is remembered.</p>
          <SegmentedControl aria-label="Glass look" value={look}
            onValueChange={(v) => setAmount(glassLooks.find((g) => g.value === v).amount)}
            items={glassLooks.map(({ value, label }) => ({ value, label }))} />
          <div className="tuner-row">
            <span className="muted small">Tinted</span>
            <Slider aria-label="Glass transparency" min={0} max={1} step={0.01} value={amount} onValueChange={setAmount} />
            <span className="muted small">Clear</span>
          </div>
        </Glass>
        <Glass className="card glass-use">
          <h3><Icon name="sparkles" /> Use it in your own site</h3>
          <p className="muted">For React, and React Native with <code>@onlymoein/liquidglass-native</code>. Buttons, switches, sliders, menus, sheets, tab bars and more.</p>
          <div className="command small-command">
            <pre><code>{install}</code></pre>
            <Button size="small" icon={<Icon name={copied ? "check" : "copy"} size={15} />} onClick={copy} aria-label="Copy the install command">
              {copied ? "Copied" : "Copy"}
            </Button>
          </div>
          <div className="glass-links">
            <Button variant="filled" icon={<Icon name="github" size={17} />} onClick={() => window.open(c.links.liquidglass, "_blank", "noopener")}>liquidglass on GitHub</Button>
            <Button onClick={() => window.open("https://onlymoein.github.io/liquidglass/", "_blank", "noopener")}>Try the live demo</Button>
          </div>
        </Glass>
      </div>
    </Section>
  );
}

function Support() {
  return (
    <section className="section">
      <Glass className="card support">
        <span className="support-cup"><Icon name="coffee" size={34} /></span>
        <div>
          <h2>MacSync is free. Coffee keeps it going.</h2>
          <p>If it saved you an afternoon of setting up a Mac, a coffee says thanks and pays for the next feature.</p>
        </div>
        <Button variant="filled" size="large" icon={<Icon name="coffee" size={20} />} onClick={() => window.open(c.links.support, "_blank", "noopener")}>
          Buy me a coffee
        </Button>
      </Glass>
    </section>
  );
}

function Footer({ theme, setTheme }) {
  return (
    <footer className="footer">
      <div className="footer-row">
        <a className="brand" href="#top"><img src={asset("icon.png")} alt="" width="26" height="26" /><span>MacSync</span></a>
        <nav aria-label="More">
          <a href={c.links.download}>Download</a>
          <a href={c.links.changelog}>Changelog</a>
          <a href={c.links.github}>GitHub</a>
          <a href={c.links.support}>Buy me a coffee</a>
        </nav>
        <SegmentedControl aria-label="Appearance" value={theme} onValueChange={setTheme}
          items={[{ value: "auto", label: "Auto" }, { value: "light", label: "Light" }, { value: "dark", label: "Dark" }]} />
      </div>
      <p className="muted small">
        Free and open source under the MIT license. Glass by <a href={c.links.liquidglass}>liquidglass</a>. Not affiliated with Apple.
      </p>
    </footer>
  );
}

export default function App() {
  const [theme, setTheme] = useTheme();
  return (
    <>
      <div className="wallpaper" aria-hidden="true"><i /><i /><i /><i /></div>
      <Nav />
      <main>
        <Hero />
        <Features />
        <Options />
        <Inside />
        <Homebrew />
        <AIApps />
        <Developers />
        <Share />
        <Progressing />
        <ArtCraft />
        <How />
        <Privacy />
        <Keyboard />
        <Faq />
        <GlassCredit />
        <Support />
      </main>
      <Footer theme={theme} setTheme={setTheme} />
    </>
  );
}
