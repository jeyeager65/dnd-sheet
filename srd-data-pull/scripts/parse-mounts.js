// Hand-parsed extraction of mounts, tack/vehicles, and large vehicles from
// the official SRD 5.2.1 markdown (equipment.md, "Mounts and Vehicles").
// Out of scope for the core character sheet, but pulled in full since we're
// no longer leaving anything out.
import { readFile, writeFile } from "node:fs/promises";

const text = await readFile(new URL("../source/srd-markdown/equipment.md", import.meta.url), "utf8");

function extractTable(tableStart) {
  const tableEnd = text.indexOf("</table>", tableStart) + "</table>".length;
  const table = text.slice(tableStart, tableEnd);
  const headers = [...table.match(/<thead>[\s\S]*?<\/thead>/)[0].matchAll(/<th>([\s\S]*?)<\/th>/g)].map((m) =>
    m[1].trim()
  );
  const bodyMatch = table.match(/<tbody>([\s\S]*?)<\/tbody>/);
  const rows = [...bodyMatch[1].matchAll(/<tr>([\s\S]*?)<\/tr>/g)].map(([, row]) => {
    const cells = [...row.matchAll(/<td>([\s\S]*?)<\/td>/g)].map((m) => m[1].trim());
    const record = {};
    headers.forEach((h, i) => (record[h] = cells[i] === "—" || cells[i] === "" ? null : cells[i]));
    return record;
  });
  return rows;
}

function extractTableAfterCaption(caption) {
  const capIdx = text.indexOf(caption);
  return extractTable(text.indexOf("<table>", capIdx));
}

function extractTableAfterHeading(heading) {
  const headIdx = text.indexOf(heading);
  return extractTable(text.indexOf("<table>", headIdx));
}

// The "Tack, Harness, and Drawn Vehicles" table has one nested group: a
// blank "Saddle" parent row followed by its 3 real sub-items (Exotic,
// Military, Riding). There's no general structural marker for this (unlike
// the weapons/armor tables' <th colspan> category rows), so rather than
// guess at a generic rule from one example, this renames those 3 known
// sub-items directly and drops the blank parent row.
const SADDLE_TYPES = new Set(["Exotic", "Military", "Riding"]);
function collapseGroups(rows, nameKey) {
  return rows
    .filter((r) => r[nameKey] !== "Saddle")
    .map((r) => (SADDLE_TYPES.has(r[nameKey]) ? { ...r, [nameKey]: `Saddle, ${r[nameKey]}` } : r));
}

const animals = extractTableAfterCaption("**Mounts and Other Animals**").map((r) => ({
  key: `srd-2024_${r.Item.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-mount`,
  name: r.Item,
  carryingCapacity: r["Carrying Capacity"],
  cost: r.Cost,
  document: "srd-2024",
}));

const tackAndVehicles = collapseGroups(extractTableAfterCaption("**Tack, Harness, and Drawn Vehicles**"), "Item").map(
  (r) => ({
    key: `srd-2024_${r.Item.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-tack`,
    name: r.Item,
    weight: r.Weight,
    cost: r.Cost,
    document: "srd-2024",
  })
);

const largeVehicles = extractTableAfterHeading("### Large Vehicles").map((r) => ({
  key: `srd-2024_${r.Ship.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-vehicle`,
  name: r.Ship,
  speed: r.Speed,
  crew: r.Crew,
  passengers: r.Passengers,
  cargoTons: r["Cargo (Tons)"],
  armorClass: r.AC,
  hitPoints: r.HP,
  damageThreshold: r["Damage Threshold"],
  cost: r.Cost,
  document: "srd-2024",
}));

console.log(`animals: ${animals.length}`);
console.log(`tack/vehicles: ${tackAndVehicles.length}`, tackAndVehicles.map((t) => t.name));
console.log(`large vehicles: ${largeVehicles.length}`);

await writeFile(new URL("../data/mounts.json", import.meta.url), JSON.stringify(animals, null, 2));
await writeFile(new URL("../data/tack-vehicles.json", import.meta.url), JSON.stringify(tackAndVehicles, null, 2));
await writeFile(new URL("../data/large-vehicles.json", import.meta.url), JSON.stringify(largeVehicles, null, 2));
