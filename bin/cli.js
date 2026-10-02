#!/usr/bin/env node
// Copies the kit's skills into an agent's skills folder. Re-running = update.
//   meeting-minutes-kit install|update|uninstall [--agents] [--dir <path>]
// Default target is ~/.claude/skills (read by Claude Code and by Freebuff).
// --agents  -> ~/.agents/skills (agents that use that convention)
// --dir     -> any folder (a project's .agents/skills, another agent's skills folder)
// Never touches ~/.claude/meeting-minutes (roster, signature, venv, voice profiles).
const fs = require("fs");
const os = require("os");
const path = require("path");

const args = process.argv.slice(2);
const cmd = args.find((a) => !a.startsWith("--")) || "help";
const flag = (n) => args.includes(n);
const dirIdx = args.indexOf("--dir");

const src = path.join(__dirname, "..", "plugin", "skills");
const pkg = require("../package.json");
const MARKER = ".installed-by-meeting-minutes-kit";

let dest = path.join(os.homedir(), ".claude", "skills");
if (dirIdx >= 0) {
  if (!args[dirIdx + 1]) { console.error("--dir needs a path"); process.exit(1); }
  dest = path.resolve(args[dirIdx + 1]);
} else if (flag("--agents")) {
  dest = path.join(os.homedir(), ".agents", "skills");
}

function pluginInstalled() {
  try {
    const f = path.join(os.homedir(), ".claude", "plugins", "installed_plugins.json");
    return /meeting-minutes@meeting-minutes-kit/.test(fs.readFileSync(f, "utf8"));
  } catch { return false; }
}

if (cmd === "install" || cmd === "update") {
  if (process.platform !== "win32") {
    console.error("meeting-minutes-kit is Windows-only for now (the setup wizard, Word check and transcription use Windows). Nothing was installed.");
    process.exit(1);
  }
  if (dest === path.join(os.homedir(), ".claude", "skills") && pluginInstalled()) {
    console.error("The meeting-minutes plugin is already installed in Claude Code. Use one route, not both. Remove the plugin with '/plugin' first.");
    process.exit(1);
  }
  fs.mkdirSync(dest, { recursive: true });
  // Skill names are generic, so never overwrite a folder this kit did not create.
  for (const name of fs.readdirSync(src)) {
    const d = path.join(dest, name);
    if (fs.existsSync(d) && !fs.existsSync(path.join(d, MARKER))) {
      console.error(`${d} exists and was not installed by this kit. Rename or remove it first.`);
      process.exit(1);
    }
  }
  for (const name of fs.readdirSync(src)) {
    const d = path.join(dest, name);
    fs.rmSync(d, { recursive: true, force: true });
    fs.cpSync(path.join(src, name), d, { recursive: true });
    fs.writeFileSync(path.join(d, MARKER), pkg.name + " " + pkg.version + "\n");
    console.log("installed skill:", name);
  }
  console.log(`\nmeeting-minutes-kit ${pkg.version} -> ${dest}`);
  console.log("Next: open your AI agent, restart it if it was already running, and say: set up the minutes tool");
} else if (cmd === "uninstall") {
  for (const name of fs.readdirSync(src)) {
    const d = path.join(dest, name);
    if (fs.existsSync(path.join(d, MARKER))) fs.rmSync(d, { recursive: true, force: true });
  }
  console.log(`skills removed from ${dest}. Your data in ~/.claude/meeting-minutes was left alone.`);
} else if (cmd === "--version" || cmd === "-v" || flag("--version")) {
  console.log(pkg.version);
} else {
  console.log("usage: meeting-minutes-kit <install|update|uninstall> [--agents] [--dir <path>]");
}
