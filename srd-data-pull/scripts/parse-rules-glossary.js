// Hand-extracts every entry in the SRD 5.2.1 Rules Glossary chapter
// (rules-glossary.md's "Rules Definitions" section) - the alphabetical
// dictionary of core rules terms (Advantage, Cover, Opportunity Attack,
// ...). Unlike parse-conditions.js (which pulls only the [Condition]-
// tagged subset for the app's Conditions catalog), this keeps every term,
// tagged or not, since the point of a glossary reference is completeness -
// some overlap with conditions.json is expected and fine.
import { readFile, writeFile } from "node:fs/promises";

const text = await readFile(new URL("../source/srd-markdown/rules-glossary.md", import.meta.url), "utf8");
const lines = text.split("\n");

// Only entries after "## Rules Definitions" - "## Glossary Conventions"
// above it isn't a term entry, it's the preamble explaining the format.
const startIdx = lines.findIndex((l) => l.trim() === "## Rules Definitions");
if (startIdx === -1) throw new Error('"## Rules Definitions" heading not found');

const headingRe = /^#### (.+?)\s*$/;
const bracketRe = /^(.*?)\s*\[(.+?)\]$/;
const anyHeadingRe = /^#{1,6} /;

const entries = [];
for (let i = startIdx; i < lines.length; i++) {
  const m = lines[i].match(headingRe);
  if (!m) continue;
  const heading = m[1].trim();
  const bracket = heading.match(bracketRe);
  const name = bracket ? bracket[1].trim() : heading;
  const tag = bracket ? bracket[2].trim() : null;

  const bodyLines = [];
  for (let j = i + 1; j < lines.length; j++) {
    if (anyHeadingRe.test(lines[j])) break;
    bodyLines.push(lines[j]);
  }
  const desc = bodyLines.join("\n").trim();
  entries.push({
    key: `srd-2024_${name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-glossary`,
    name,
    tag,
    desc,
  });
}

console.log(`Extracted ${entries.length} glossary entries`);

await writeFile(
  new URL("../data/rules-glossary.json", import.meta.url),
  JSON.stringify(entries, null, 2)
);
