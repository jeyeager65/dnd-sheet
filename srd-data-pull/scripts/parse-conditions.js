// Hand-targeted extraction of the 15 official 2024 conditions from the full
// SRD 5.2.1 markdown text (rules-glossary.md).
import { readFile, writeFile } from "node:fs/promises";

const text = await readFile(new URL("../source/srd-markdown/rules-glossary.md", import.meta.url), "utf8");
const lines = text.split("\n");

const headingRe = /^#### (.+?) \[Condition\]\s*$/;
const anyHeadingRe = /^#{1,6} /;

const conditions = [];
for (let i = 0; i < lines.length; i++) {
  const m = lines[i].match(headingRe);
  if (!m) continue;
  const name = m[1].trim();
  const bodyLines = [];
  for (let j = i + 1; j < lines.length; j++) {
    if (anyHeadingRe.test(lines[j])) break;
    bodyLines.push(lines[j]);
  }
  const desc = bodyLines.join("\n").trim();
  conditions.push({
    key: `srd-2024_${name.toLowerCase()}-condition`,
    name,
    desc,
    document: "srd-2024",
  });
}

console.log(`Extracted ${conditions.length} conditions:`, conditions.map((c) => c.name).join(", "));

await writeFile(
  new URL("../data/conditions.json", import.meta.url),
  JSON.stringify(conditions, null, 2)
);
