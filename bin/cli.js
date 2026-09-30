#!/usr/bin/env node
// Copies the plugin's skills into ~/.claude/skills. Re-running = update.
// Never touches ~/.claude/meeting-minutes (roster, signature, venv, voice profiles).
const fs = require("fs");
const os = require("os");
const path = require("path");

const cmd = process.argv[2] || "help";
const src = path.join(__dirname, "..", "plugin", "skills");
const dest = path.join(os.homedir(), ".claude", "skills");
const pkg = require("../package.json");
const MARKER = ".installed-by-meeting-minutes-kit";

function pluginInstalled() {
  try {
    const f = path.join(os.homedir(), ".claude", "plugins", "installed_plugins.json");
    return /meeting-minutes@meeting-minutes-kit/.test(fs.readFileSync(f, "utf8"));
  } catch { return false; }
}

if (cmd === "install" || cmd === "update") {
  if (pluginInstalled()) {
    console.error("The meeting-minutes plugin is already installed. Use one route, not both. Run '/plugin' in Claude Code to remove it first.");
    process.exit(1);
  }
  // Skill names are generic, so never overwrite a folder this kit did not create.
  for (const name of fs.readdirSync(src)) {
    const d = path.join(dest, name);
    if (fs.existsSync(d) && !fs.existsSync(path.join(d, MARKER))) {
      console.error(`~/.claude/skills/${name} exists and was not installed by this kit. Rename or remove it first.`);
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
  console.log("Next: open Claude Code and say: set up the minutes tool");
} else if (cmd === "uninstall") {
  for (const name of fs.readdirSync(src)) {
    const d = path.join(dest, name);
    if (fs.existsSync(path.join(d, MARKER))) fs.rmSync(d, { recursive: true, force: true });
  }
  console.log("skills removed. Your data in ~/.claude/meeting-minutes was left alone.");
} else if (cmd === "--version" || cmd === "-v") {
  console.log(pkg.version);
} else {
  console.log("usage: meeting-minutes-kit <install|update|uninstall|--version>");
}
