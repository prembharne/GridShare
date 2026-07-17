import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const bundleDir = path.join(root, "markdown_files");
const ignoredDirs = new Set([
  ".git",
  ".agents",
  "node_modules",
  "runtime",
  "markdown_files"
]);

function walk(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    if (entry.isDirectory()) {
      if (!ignoredDirs.has(entry.name)) {
        files.push(...walk(path.join(dir, entry.name)));
      }
      continue;
    }

    if (entry.isFile() && entry.name.toLowerCase().endsWith(".md")) {
      files.push(path.join(dir, entry.name));
    }
  }

  return files;
}

function toPosix(relativePath) {
  return relativePath.split(path.sep).join("/");
}

fs.rmSync(bundleDir, { recursive: true, force: true });
fs.mkdirSync(bundleDir, { recursive: true });

const markdownFiles = walk(root).sort((a, b) => a.localeCompare(b));
const indexLines = [
  "# Markdown Files Bundle",
  "",
  "This folder mirrors every Markdown file in the project, preserving original relative paths.",
  "",
  "## Files",
  ""
];

for (const source of markdownFiles) {
  const relative = path.relative(root, source);
  const destination = path.join(bundleDir, relative === path.basename(relative) ? "root" : "", relative);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);

  const bundledRelative = path.relative(bundleDir, destination);
  indexLines.push(`- ${toPosix(relative)} -> ${toPosix(bundledRelative)}`);
}

fs.writeFileSync(path.join(bundleDir, "INDEX.md"), `${indexLines.join("\n")}\n`, "utf8");
console.log(`Synced ${markdownFiles.length} Markdown files into markdown_files/.`);
