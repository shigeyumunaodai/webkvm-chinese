#!/usr/bin/env node
// check-i18n — compares the en/es/ca/zh message dictionaries in
// src/lib/i18n.svelte.js and fails if their key sets are not identical.
//
// i18n.svelte.js uses Svelte 5 $state, so it can't be imported directly
// in a plain Node process. Instead we extract each top-level language
// object with a brace-matching scanner and evaluate it as a plain object
// literal (all keys are quoted single/double strings, no functions).
//
// For Chinese it additionally verifies that every `{placeholder}` in the
// English value also appears in the Chinese value, with the same
// multiplicity. (The Spanish and Catalan dictionaries predate this
// contract and still carry two known plural deviations, so the stricter
// check is zh-only.)
//
// Exit codes: 0 = symmetric, 1 = asymmetric (missing keys printed).
import { readFileSync, readdirSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

// Flags are filtered out so a flag is never mistaken for the path of
// the dictionary to check.
const args = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const target =
  args[0] ||
  fileURLToPath(new URL("../frontend/src/lib/i18n.svelte.js", import.meta.url));

let src;
try {
  src = readFileSync(target, "utf8");
} catch {
  console.error(`check-i18n: cannot read ${target}`);
  process.exit(1);
}

// Extract the body of `messages.<key> = { ... }` (top-level object) with
// brace matching so nested braces inside string values are handled by the
// same counter (strings never contain unbalanced braces in this file).
function extractObject(src, key) {
  const re = new RegExp(`\\b${key}\\s*:\\s*\\{`);
  const m = re.exec(src);
  if (!m) return null;
  let i = src.indexOf("{", m.index);
  let depth = 0;
  for (; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}") {
      depth--;
      if (depth === 0) return src.slice(m.index + m[0].length - 1, i + 1);
    }
  }
  return null;
}

function flatKeys(obj, prefix = "", out = new Set()) {
  for (const [k, v] of Object.entries(obj)) {
    const kk = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === "object" && !Array.isArray(v)) flatKeys(v, kk, out);
    else out.add(kk);
  }
  return out;
}

function flatValues(obj, prefix = "", out = new Map()) {
  for (const [k, v] of Object.entries(obj)) {
    const kk = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === "object" && !Array.isArray(v)) flatValues(v, kk, out);
    else out.set(kk, v);
  }
  return out;
}

function placeholders(value) {
  return [...String(value).matchAll(/\{([A-Za-z0-9_]+)\}/g)]
    .map((m) => m[1])
    .sort();
}

const dicts = {};
for (const lang of ["en", "es", "ca", "zh"]) {
  const text = extractObject(src, lang);
  if (!text) {
    console.error(`check-i18n: could not find messages.${lang} block`);
    process.exit(1);
  }
  try {
    dicts[lang] = Function(`"use strict"; return (${text});`)();
  } catch (err) {
    console.error(
      `check-i18n: failed to evaluate messages.${lang}: ${err.message}`,
    );
    process.exit(1);
  }
}

const keys = Object.fromEntries(
  Object.entries(dicts).map(([l, d]) => [l, flatKeys(d)]),
);

let failed = false;
for (const [a, b] of [
  ["en", "es"],
  ["en", "ca"],
  ["en", "zh"],
  ["es", "ca"],
]) {
  const missingInB = [...keys[a]].filter((k) => !keys[b].has(k));
  const missingInA = [...keys[b]].filter((k) => !keys[a].has(k));
  if (missingInB.length) {
    failed = true;
    console.error(
      `check-i18n: ${missingInB.length} key(s) present in "${a}" but missing in "${b}":`,
    );
    for (const k of missingInB) console.error(`  - ${k}`);
  }
  if (missingInA.length) {
    failed = true;
    console.error(
      `check-i18n: ${missingInA.length} key(s) present in "${b}" but missing in "${a}":`,
    );
    for (const k of missingInA) console.error(`  - ${k}`);
  }
}

// --- Placeholder parity for Chinese ------------------------------------
//
// A translation that drops or renames a `{placeholder}` renders the raw
// token in the UI (or silently loses the value); Chinese is held to the
// exact same placeholder multiset as English.
{
  const enValues = flatValues(dicts.en);
  const zhValues = flatValues(dicts.zh);
  const mismatches = [];
  for (const [key, enValue] of enValues) {
    if (!zhValues.has(key)) continue;
    const enPh = placeholders(enValue);
    const zhPh = placeholders(zhValues.get(key));
    if (enPh.join(",") !== zhPh.join(",")) {
      mismatches.push(`${key} (en: ${enPh.join(",") || "none"} / zh: ${zhPh.join(",") || "none"})`);
    }
  }
  if (mismatches.length) {
    failed = true;
    console.error(
      `check-i18n: ${mismatches.length} zh key(s) with mismatched placeholders:`,
    );
    for (const m of mismatches) console.error(`  - ${m}`);
  }
}

// --- Used-but-undefined keys -------------------------------------------
//
// Symmetry alone does not catch the failure the user actually sees: a
// t('foo.bar') whose key exists in no dictionary renders as the raw key
// in the interface. That is a visible bug, so it fails the check.
//
// The reverse (a defined key nobody calls) is only dead weight, so it is
// reported as a count and never fails: the dictionaries are also used by
// tooling and several keys are reached through the computed lookups
// below, which no static scan can resolve.
const srcDir = fileURLToPath(new URL("../frontend/src", import.meta.url));

function walk(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name.startsWith(".")) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (
      /\.(svelte|js|ts)$/.test(entry.name) &&
      !entry.name.endsWith(".test.js")
    ) {
      out.push(full);
    }
  }
  return out;
}

// t('a.b') / t("a.b") / t(`a.b`), with or without a second argument.
// Group 3 captures a trailing "+", which marks the literal as the
// prefix of a key built at runtime — t('vms.cat_' + category).
const T_CALL = /\bt\(\s*(['"`])([^'"`$\n]+?)\1\s*(\+)?/g;

// t(`vms.cat_${category}`) — a template literal whose interpolation
// starts partway through. Everything before the first ${ is a prefix.
const T_TEMPLATE = /\bt\(\s*`([^`$\n]*)\$\{/g;

// Keys handed around as data rather than called directly: a lookup
// table (MOVE_STAGES), a { labelKey: 'nav.vms' } menu entry, a ternary
// inside the call — t(copy ? 'storage.volumeCopied' : '…'). Rather than
// chase each shape, any string literal in the source that happens to be
// a defined key counts as a reference. A dotted literal that is not in
// the dictionary is ignored, so this cannot invent keys; the worst case
// is calling a genuinely dead key alive, which only leaves a little
// dead weight instead of deleting a string the UI still needs.
const KEY_LITERAL = /(['"`])([A-Za-z][\w]*(?:\.[\w]+)+)\1/g;

const used = new Map(); // exact key -> first file that used it
const prefixes = new Set(); // computed key prefixes
for (const file of walk(srcDir)) {
  if (file.endsWith("i18n.svelte.js")) continue; // the dictionary itself
  const text = readFileSync(file, "utf8");
  const rel = relative(srcDir, file);

  for (const m of text.matchAll(T_CALL)) {
    const key = m[2];
    // Only dotted keys are dictionary lookups; a bare word is almost
    // always some other single-letter function named t.
    if (!key.includes(".")) continue;
    if (m[3]) {
      // A computed key: the suffix comes from a variable, so the
      // exact key cannot be known here. Every dictionary key sharing
      // the prefix counts as reachable.
      prefixes.add(key);
      continue;
    }
    if (!used.has(key)) used.set(key, rel);
  }
  for (const m of text.matchAll(T_TEMPLATE)) {
    if (m[1].includes(".")) prefixes.add(m[1]);
  }
  for (const m of text.matchAll(KEY_LITERAL)) {
    if (keys.en.has(m[2]) && !used.has(m[2])) used.set(m[2], rel);
  }
}

// A prefix that matches no key at all is still a bug: it means the
// whole family was renamed or never written.
for (const p of prefixes) {
  if (![...keys.en].some((k) => k.startsWith(p))) {
    failed = true;
    console.error(
      `check-i18n: computed key prefix "${p}" matches no defined key`,
    );
  }
}

const matchesPrefix = (k) => [...prefixes].some((p) => k.startsWith(p));
const undefinedKeys = [...used].filter(([k]) => !keys.en.has(k));
if (undefinedKeys.length) {
  failed = true;
  console.error(
    `check-i18n: ${undefinedKeys.length} key(s) used in the UI but defined nowhere:`,
  );
  for (const [k, file] of undefinedKeys) console.error(`  - ${k}  (${file})`);
}

const orphans = [...keys.en].filter((k) => !used.has(k) && !matchesPrefix(k));

if (failed) {
  console.error(
    `check-i18n: FAIL (en=${keys.en.size}, es=${keys.es.size}, ca=${keys.ca.size}, zh=${keys.zh.size})`,
  );
  process.exit(1);
}
console.log(
  `check-i18n: OK (en=${keys.en.size}, es=${keys.es.size}, ca=${keys.ca.size}` +
    `, zh=${keys.zh.size}, used=${used.size}, unreferenced=${orphans.length})`,
);
// --unreferenced prints the unused keys, for a manual cleanup pass.
// Not part of the pass/fail contract: see the note above.
//
// Treat the list as a starting point, not a delete list. The scan is
// deliberately generous, but a key can still be reached in ways no
// regex sees, and the remaining entries have generic leaf names
// ("name", "loading", "back") that are easy to confuse with an
// identically named key elsewhere. Confirm each one by hand.
if (process.argv.includes("--unreferenced")) {
  for (const k of orphans) console.log(k);
}
