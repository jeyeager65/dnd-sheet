// Hand-targeted extraction of the 2024 language lists from the official SRD
// 5.2.1 markdown (character-creation.md), since Open5e's "core" (2014)
// language data is missing "Common Sign Language" (a 2024 addition) and
// uses the old Standard/Exotic split instead of 2024's Standard/Rare split.
import { readFile, writeFile } from "node:fs/promises";

const text = await readFile(new URL("../source/srd-markdown/character-creation.md", import.meta.url), "utf8");

function extractRows(sectionTitle) {
  const start = text.indexOf(sectionTitle);
  const tableStart = text.indexOf("<table>", start);
  const tableEnd = text.indexOf("</table>", tableStart) + "</table>".length;
  const table = text.slice(tableStart, tableEnd);
  const rows = [...table.matchAll(/<tr>([\s\S]*?)<\/tr>/g)].slice(1); // skip header row
  return rows.map(([, row]) =>
    [...row.matchAll(/<td>([\s\S]*?)<\/td>/g)].map((m) => m[1].replace(/\*/g, "").trim())
  );
}

// Standard Languages table: columns are [1d12 roll, Language] - keep only the name.
const standard = extractRows("**Standard Languages**")
  .map((cells) => cells[1])
  .filter(Boolean);

// Rare Languages table: two side-by-side "Language" columns, both are names.
const rare = extractRows("**Rare Languages**")
  .flatMap((cells) => cells)
  .filter(Boolean);

const languages = [
  ...standard.map((name) => ({ name, category: "Standard" })),
  ...rare.map((name) => ({ name, category: "Rare" })),
].map((l) => ({
  key: `srd-2024_${l.name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-language`,
  name: l.name,
  category: l.category,
  desc:
    l.name === "Primordial"
      ? "Includes the Aquan, Auran, Ignan, and Terran dialects. Creatures that know one of these dialects can communicate with those that know a different one."
      : "",
  document: "srd-2024",
  source:
    "hand-extracted from SRD 5.2.1 character-creation.md (Open5e's 'core' language data is 2014-era and missing the 2024 addition of Common Sign Language)",
}));

console.log(`Extracted ${languages.length} languages:`, languages.map((l) => l.name).join(", "));

await writeFile(
  new URL("../data/languages.json", import.meta.url),
  JSON.stringify(languages, null, 2)
);
