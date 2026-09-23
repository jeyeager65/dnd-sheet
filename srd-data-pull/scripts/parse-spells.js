// Hand-parsed extraction of spells from the official SRD 5.2.1 markdown
// (spells.md). The file also contains creature stat blocks referenced by
// some spells (e.g. Animate Objects' "Animated Object", Find Steed's
// "Otherworldly Steed") using the same #### heading level as real spells,
// plus a few intro-section #### headings before the spell list starts. Both
// are filtered out by requiring the "_Level N School (Classes)_" tag line
// immediately after the heading - only real spells have it.
import { readFile, writeFile } from "node:fs/promises";

const text = await readFile(new URL("../source/srd-markdown/spells.md", import.meta.url), "utf8");

const TAG_RE = /^_(?:Level (\d+) ([A-Za-z]+)|([A-Za-z]+) Cantrip)(?: \(([^)]+)\))?_$/;

const parts = text.split(/\n#### /).slice(1);

const spells = [];
for (const part of parts) {
  const nlIdx = part.indexOf("\n");
  const name = part.slice(0, nlIdx).trim();
  const rest = part.slice(nlIdx + 1).trim();

  const lines = rest.split("\n");
  const tagLine = lines[0].trim();
  const tagMatch = tagLine.match(TAG_RE);
  if (!tagMatch) continue; // not a spell (stat block or stray heading)

  const [, levelStr, school1, school2, classesStr] = tagMatch;
  const level = levelStr ? parseInt(levelStr, 10) : 0; // cantrip = level 0
  const school = school1 || school2;
  const classes = classesStr ? classesStr.split(",").map((c) => c.trim()) : [];

  const body = lines.slice(1).join("\n").trim();
  const castingTime = body.match(/\*\*Casting Time:\*\*\s*(.+)/)?.[1]?.trim() ?? null;
  const range = body.match(/\*\*Range:\*\*\s*(.+)/)?.[1]?.trim() ?? null;
  const components = body.match(/\*\*Components:\*\*\s*(.+)/)?.[1]?.trim() ?? null;
  const duration = body.match(/\*\*Duration:\*\*\s*(.+)/)?.[1]?.trim() ?? null;

  const descStart = body.indexOf(
    body.match(/\*\*Duration:\*\*.*/)[0]
  ) + body.match(/\*\*Duration:\*\*.*/)[0].length;
  let desc = body.slice(descStart).trim();

  // Scaling note is written as "_Using a Higher-Level Spell Slot._ ..." or
  // "_Cantrip Upgrade._ ..." at the end of the description - split it out.
  let higherLevel = null;
  const scalingMatch = desc.match(/\n_((?:Using a Higher-Level Spell Slot|Cantrip Upgrade))\._\s*([\s\S]*)/);
  if (scalingMatch) {
    higherLevel = scalingMatch[2].trim();
    desc = desc.slice(0, scalingMatch.index).trim();
  }

  spells.push({
    key: `srd-2024_${name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-spell`,
    name,
    level,
    school,
    classes,
    ritual: /Ritual/.test(castingTime ?? ""),
    castingTime,
    range,
    components,
    concentration: /^Concentration/.test(duration ?? ""),
    duration,
    desc,
    higherLevel,
    document: "srd-2024",
  });
}

console.log(`spells: ${spells.length}`);
const byLevel = {};
for (const s of spells) byLevel[s.level] = (byLevel[s.level] ?? 0) + 1;
console.log("by level:", byLevel);

await writeFile(new URL("../data/spells.json", import.meta.url), JSON.stringify(spells, null, 2));
