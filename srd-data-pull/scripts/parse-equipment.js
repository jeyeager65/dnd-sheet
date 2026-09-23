// Hand-parsed extraction of weapons and armor from the official SRD 5.2.1
// markdown (equipment.md). Both are clean HTML tables with category
// sub-header rows (e.g. "Simple Melee Weapons"), so this is straightforward -
// unlike spells/classes, which are prose and will need more careful parsing.
import { readFile, writeFile } from "node:fs/promises";

const text = await readFile(new URL("../source/srd-markdown/equipment.md", import.meta.url), "utf8");

function extractTable(sectionTitle) {
  const start = text.indexOf(sectionTitle);
  const tableStart = text.indexOf("<table>", start);
  const tableEnd = text.indexOf("</table>", tableStart) + "</table>".length;
  const table = text.slice(tableStart, tableEnd);

  const headers = table.match(/<thead>[\s\S]*?<\/thead>/)[0];
  const columns = [...headers.matchAll(/<th>([\s\S]*?)<\/th>/g)].map((m) => m[1].trim());

  const bodyMatch = table.match(/<tbody>([\s\S]*?)<\/tbody>/);
  const rows = [...bodyMatch[1].matchAll(/<tr>([\s\S]*?)<\/tr>/g)];

  const items = [];
  let category = null;
  for (const [, row] of rows) {
    const subHeader = row.match(/<th colspan="\d+"><em>([\s\S]*?)<\/em><\/th>/);
    if (subHeader) {
      category = subHeader[1].trim();
      continue;
    }
    const cells = [...row.matchAll(/<td>([\s\S]*?)<\/td>/g)].map((m) => m[1].trim());
    const record = { category };
    columns.forEach((col, i) => {
      record[col] = cells[i] === "—" ? null : cells[i];
    });
    items.push(record);
  }
  return items;
}

const rawWeapons = extractTable("**Weapons**");
const weapons = rawWeapons.map((w) => ({
  key: `srd-2024_${w.Name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-weapon`,
  name: w.Name,
  category: w.category, // e.g. "Simple Melee Weapons"
  damage: w.Damage,
  properties: w.Properties ? w.Properties.split(",").map((p) => p.trim()) : [],
  mastery: w.Mastery,
  weight: w.Weight,
  cost: w.Cost,
  document: "srd-2024",
}));

const rawArmor = extractTable("**Armor**");
const armor = rawArmor.map((a) => ({
  key: `srd-2024_${a.Armor.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-armor`,
  name: a.Armor,
  category: a.category, // e.g. "Light Armor (1 Minute to Don or Doff)"
  armorClass: a["Armor Class (AC)"],
  strength: a.Strength,
  stealth: a.Stealth === "Disadvantage",
  weight: a.Weight,
  cost: a.Cost,
  document: "srd-2024",
}));

console.log(`weapons: ${weapons.length}`);
console.log(`armor: ${armor.length}`);

await writeFile(new URL("../data/weapons.json", import.meta.url), JSON.stringify(weapons, null, 2));
await writeFile(new URL("../data/armor.json", import.meta.url), JSON.stringify(armor, null, 2));
