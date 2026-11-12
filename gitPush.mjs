#!/usr/bin/env node
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const APP_PATH = resolve(__dirname);
process.env.BUILD_LOG_DIR = APP_PATH;

const candidates = [
  resolve(__dirname, "..", "the-good-library", "appScripts", "gitPush.mjs"),
  resolve(
    __dirname,
    "node_modules",
    "@mrjames12345",
    "the-good-library",
    "appScripts",
    "gitPush.mjs"
  ),
  resolve(__dirname, "appScripts", "gitPush.mjs"),
];

const libScript = candidates.find((candidate) => existsSync(candidate));
if (!libScript) {
  console.error(
    "ERROR: Could not locate the-good-library/appScripts/gitPush.mjs."
  );
  process.exit(1);
}

const child = spawn(
  process.execPath,
  [libScript, APP_PATH, ...process.argv.slice(2)],
  {
    stdio: "inherit",
  }
);
child.on("close", (code) => process.exit(code ?? 0));
