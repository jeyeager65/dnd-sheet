// Splits a handful of the SRD's narrative rules chapters into one entry per
// top-level ("## ") section, keeping each section's nested "###"/"####"
// subsections as part of its markdown body rather than atomizing further -
// unlike the glossary (whose "####" entries are each a short, standalone
// definition), these chapters build on each other within a section (e.g.
// "Combat" walks through initiative, movement, attacks, cover... as one
// continuous read), so splitting any finer would fragment that flow.
//
// Covers the three chapters with no other parser: playing-the-game.md (core
// D20 Test/action/combat/damage rules), gameplay-toolbox.md (optional rules
// - travel, hazards, poison, traps, encounter building), and
// character-creation.md (chargen steps, leveling, multiclassing, trinkets -
// NOT character-origins.md, which parse-origins.js already covers in full
// via backgrounds.json/species.json).
import { readFile, writeFile } from "node:fs/promises";

const CHAPTERS = [
  { file: "playing-the-game.md", out: "playing-the-game.json" },
  { file: "gameplay-toolbox.md", out: "gameplay-toolbox.json" },
  { file: "character-creation.md", out: "character-creation.json" },
];

const sectionRe = /^## (.+?)\s*$/;

for (const { file, out } of CHAPTERS) {
  const text = await readFile(new URL(`../source/srd-markdown/${file}`, import.meta.url), "utf8");
  const lines = text.split("\n");

  const entries = [];
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(sectionRe);
    if (!m) continue;
    const name = m[1].trim();

    const bodyLines = [];
    for (let j = i + 1; j < lines.length; j++) {
      if (sectionRe.test(lines[j])) break;
      bodyLines.push(lines[j]);
    }
    const desc = bodyLines.join("\n").trim();
    entries.push({
      key: `srd-2024_${name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-chapter`,
      name,
      desc,
    });
  }

  console.log(`${file}: extracted ${entries.length} sections -`, entries.map((e) => e.name).join(", "));

  await writeFile(
    new URL(`../data/${out}`, import.meta.url),
    JSON.stringify(entries, null, 2)
  );
}
