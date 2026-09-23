// Hand-parsed extraction of backgrounds and species from the official SRD
// 5.2.1 markdown (character-origins.md).
import { readFile, writeFile } from "node:fs/promises";

const text = await readFile(new URL("../source/srd-markdown/character-origins.md", import.meta.url), "utf8");

function sliceBetween(startMarker, endMarker) {
  const start = text.indexOf(startMarker);
  if (start === -1) throw new Error(`marker not found: ${startMarker}`);
  const end = endMarker ? text.indexOf(endMarker, start) : text.length;
  return text.slice(start + startMarker.length, end === -1 ? text.length : end);
}

// Splits a section's text into { name, body } per "#### Name" heading.
function splitEntries(section) {
  const parts = section.split(/\n#### /).slice(1); // first chunk before first heading is intro text
  return parts.map((part) => {
    const newlineIdx = part.indexOf("\n");
    const name = part.slice(0, newlineIdx).trim();
    const body = part.slice(newlineIdx + 1).trim();
    return { name, body };
  });
}

function field(body, label) {
  const m = body.match(new RegExp(`\\*\\*${label}:\\*\\*\\s*(.+)`));
  return m ? m[1].trim() : null;
}

// --- Backgrounds ---
const backgroundsSection = sliceBetween("### Background Descriptions", "## Character Species");
const backgrounds = splitEntries(backgroundsSection).map(({ name, body }) => ({
  key: `srd-2024_${name.toLowerCase()}-background`,
  name,
  abilityScores: field(body, "Ability Scores")?.split(",").map((s) => s.trim()) ?? [],
  feat: field(body, "Feat")?.replace(/\s*\(see "Feats"\)/, "") ?? null,
  skillProficiencies: field(body, "Skill Proficiencies")?.split(/,| and /).map((s) => s.trim()).filter(Boolean) ?? [],
  toolProficiency: field(body, "Tool Proficiency"),
  equipment: field(body, "Equipment"),
  document: "srd-2024",
}));

// --- Species ---
const speciesSection = sliceBetween("### Species Descriptions", null);
const species = splitEntries(speciesSection).map(({ name, body }) => {
  const creatureType = field(body, "Creature Type");
  const size = field(body, "Size");
  const speed = field(body, "Speed");

  // Traits are written as "_Trait Name._ description text..." paragraphs.
  // Some traits (e.g. Dragonborn's Draconic Ancestry) reference an embedded
  // reference table - pull those out as structured data (caption + rows)
  // before stripping them from the prose, rather than just discarding them.
  const afterFields = body.slice(body.indexOf(`**Speed:** ${speed}`) + `**Speed:** ${speed}`.length);

  const tables = [];
  const withoutTables = afterFields.replace(
    /\n\n\*\*([^\n*]+)\*\*\n\n<table>([\s\S]*?)<\/table>/g,
    (_, caption, tableHtml) => {
      const headers = [...tableHtml.matchAll(/<th>([\s\S]*?)<\/th>/g)].map((m) => m[1].trim());
      const rows = [...tableHtml.matchAll(/<tr>([\s\S]*?)<\/tr>/g)]
        .slice(1) // skip header row
        .map(([, row]) => [...row.matchAll(/<td>([\s\S]*?)<\/td>/g)].map((m) => m[1].trim()));
      tables.push({ caption: caption.trim(), headers, rows });
      return "";
    }
  );

  const traitBlocks = withoutTables.split(/\n_(?=[A-Z][^_]*\._)/).map((s) => s.trim()).filter(Boolean);

  const traits = [];
  for (const block of traitBlocks) {
    const m = block.match(/^_?([^_]+)\._\s*([\s\S]*)/);
    if (!m) continue; // leading intro sentence before the first trait, not a trait itself
    traits.push({ name: m[1].trim(), desc: m[2].trim() });
  }

  return {
    key: `srd-2024_${name.toLowerCase()}-species`,
    name,
    creatureType,
    size,
    speed,
    traits,
    tables,
    document: "srd-2024",
  };
});

console.log(`backgrounds: ${backgrounds.length}`, backgrounds.map((b) => b.name));
console.log(`species: ${species.length}`, species.map((s) => s.name));
console.log(`species trait counts:`, species.map((s) => `${s.name}=${s.traits.length}`).join(", "));

await writeFile(new URL("../data/backgrounds.json", import.meta.url), JSON.stringify(backgrounds, null, 2));
await writeFile(new URL("../data/species.json", import.meta.url), JSON.stringify(species, null, 2));
