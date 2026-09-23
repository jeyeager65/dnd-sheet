// Hand-parsed extraction of adventuring gear and tools from the official
// SRD 5.2.1 markdown (equipment.md), including the sub-variant tables for
// "Varies"-cost items (Ammunition, Arcane/Druidic Focus, Holy Symbol,
// Gaming Set, Musical Instrument) rather than leaving those as one generic
// entry each.
import { readFile, writeFile } from "node:fs/promises";

const text = await readFile(new URL("../source/srd-markdown/equipment.md", import.meta.url), "utf8");

function sliceBetween(startMarker, endMarker) {
  const start = text.indexOf(startMarker);
  const end = text.indexOf(endMarker, start);
  return text.slice(start, end === -1 ? text.length : end);
}

function extractTableAfter(marker, fromIndex = 0) {
  const capIdx = text.indexOf(marker, fromIndex);
  if (capIdx === -1) return null;
  const tableStart = text.indexOf("<table>", capIdx);
  const tableEnd = text.indexOf("</table>", tableStart) + "</table>".length;
  const table = text.slice(tableStart, tableEnd);
  const headers = [...table.match(/<thead>[\s\S]*?<\/thead>/)[0].matchAll(/<th>([\s\S]*?)<\/th>/g)].map((m) =>
    m[1].trim()
  );
  const bodyMatch = table.match(/<tbody>([\s\S]*?)<\/tbody>/);
  const rows = [...bodyMatch[1].matchAll(/<tr>([\s\S]*?)<\/tr>/g)].map(([, row]) => {
    const cells = [...row.matchAll(/<td>([\s\S]*?)<\/td>/g)].map((m) => m[1].trim());
    const record = {};
    headers.forEach((h, i) => (record[h] = cells[i] === "—" ? null : cells[i]));
    return record;
  });
  return { end: tableEnd, rows };
}

// --- Master "Adventuring Gear" table: authoritative Item/Weight/Cost for every gear item ---
const masterTable = extractTableAfter("**Adventuring Gear**");
const masterByName = new Map(masterTable.rows.map((r) => [r.Item, r]));

// --- Ammunition sub-table (Type/Amount/Storage/Weight/Cost) ---
const ammoTable = extractTableAfter("**Ammunition**", masterTable.end);
const ammoVariants = ammoTable.rows.map((r) => ({
  name: r.Type,
  amount: r.Amount,
  storage: r.Storage,
  weight: r.Weight,
  cost: r.Cost,
}));

// --- Prose descriptions: "#### Name (Cost)" blocks ---
const gearSection = sliceBetween("## Adventuring Gear", "## Mounts and Vehicles");
const gearParts = gearSection.split(/\n#### /).slice(1);

function makeKey(name, suffix) {
  return `srd-2024_${name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${suffix}`;
}

// Simple "Name (cost)" or "Name (cost, weight)" variant-list parser, used
// for tool "Variants:" fields (Gaming Set, Musical Instrument).
function parseInlineVariants(str) {
  if (!str) return [];
  return [...str.matchAll(/([^,()]+?)\s*\(([^)]+)\)/g)].map(([, name, details]) => {
    const parts = details.split(",").map((s) => s.trim());
    const cost = parts.find((p) => /GP|SP|CP|PP|EP/.test(p)) ?? parts[0] ?? null;
    const weight = parts.find((p) => /lb\.?/.test(p)) ?? null;
    return { name: name.trim(), cost, weight };
  });
}

const descByBaseName = new Map();
for (const part of gearParts) {
  const headerLine = part.slice(0, part.indexOf("\n"));
  let desc = part.slice(part.indexOf("\n") + 1).trim();
  desc = desc.replace(/\*\*[^\n*]+\*\*\n\n<table>[\s\S]*?<\/table>/g, "").trim();
  const m = headerLine.match(/^(.+?)\s*\([^)]+\)\s*$/);
  const baseName = (m ? m[1] : headerLine).trim();
  if (!descByBaseName.has(baseName)) descByBaseName.set(baseName, desc);
}

const VARIANT_TABLE_CAPTIONS = {
  "Arcane Focus": "**Arcane Focuses**",
  "Druidic Focus": "**Druidic Focuses**",
  "Holy Symbol": "**Holy Symbols**",
};

const gear = [...masterByName.keys()].map((name) => {
  const row = masterByName.get(name);
  const baseName = name.replace(/\s*\([^)]+\)\s*$/, "");
  const entry = {
    key: makeKey(name, "gear"),
    name,
    weight: row.Weight,
    cost: row.Cost,
    desc: descByBaseName.get(name) ?? descByBaseName.get(baseName) ?? null,
    document: "srd-2024",
  };

  if (name === "Ammunition") entry.variants = ammoVariants;
  else if (VARIANT_TABLE_CAPTIONS[name]) {
    const t = extractTableAfter(VARIANT_TABLE_CAPTIONS[name]);
    const cols = Object.keys(t.rows[0]);
    entry.variants = t.rows.map((r) => ({ name: r[cols[0]], weight: r.Weight, cost: r.Cost }));
  }

  return entry;
});

// --- Tools: "**Name (Cost)**" + labeled fields ---
const toolsSection = sliceBetween("## Tools", "## Adventuring Gear");
const toolParts = toolsSection.split(/\n\*\*(?=[A-Z][^*]+\([^)]+\)\*\*)/).slice(1);
function field(body, label) {
  const m = body.match(new RegExp(`\\*\\*${label}:\\*\\*\\s*([^\\n]+?)(?=\\s*\\*\\*[A-Za-z]|\\n|$)`));
  return m ? m[1].trim() : null;
}
const tools = toolParts.map((part) => {
  const headerEnd = part.indexOf("**");
  const headerLine = part.slice(0, headerEnd);
  const body = part.slice(headerEnd + 2);
  const m = headerLine.match(/^(.+?)\s*\(([^)]+)\)\s*$/);
  const name = m ? m[1].trim() : headerLine.trim();
  const variantsRaw = field(body, "Variants");
  return {
    key: makeKey(name, "tool"),
    name,
    cost: m ? m[2].trim() : null,
    ability: field(body, "Ability"),
    weight: field(body, "Weight"),
    utilize: field(body, "Utilize"),
    craft: field(body, "Craft"),
    variants: variantsRaw ? parseInlineVariants(variantsRaw) : undefined,
    document: "srd-2024",
  };
});

console.log(`gear: ${gear.length} (master table rows: ${masterTable.rows.length})`);
console.log(`  with variants: ${gear.filter((g) => g.variants).map((g) => `${g.name} (${g.variants.length})`).join(", ")}`);
console.log(`tools: ${tools.length}`);
console.log(`  with variants: ${tools.filter((t) => t.variants).map((t) => `${t.name} (${t.variants.length})`).join(", ")}`);
console.log(`  gear entries missing a desc match: ${gear.filter((g) => !g.desc).map((g) => g.name).join(", ") || "none"}`);

await writeFile(new URL("../data/gear.json", import.meta.url), JSON.stringify(gear, null, 2));
await writeFile(new URL("../data/tools.json", import.meta.url), JSON.stringify(tools, null, 2));
