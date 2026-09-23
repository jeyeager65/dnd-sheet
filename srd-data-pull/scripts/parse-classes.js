// Hand-parsed extraction of classes + their single SRD subclass from the
// official SRD 5.2.1 markdown (classes.md). Each class follows a consistent
// template: a "Core X Traits" key/value table, an "X Features" level
// progression table (column count varies - casters add Cantrips/Prepared
// Spells/Spell Slot columns), then "#### Level N: Feature Name" blocks for
// each feature, then one "### X Subclass: Name" section with its own
// "#### Level N: Feature Name" blocks.
import { readFile, writeFile } from "node:fs/promises";

const text = await readFile(new URL("../source/srd-markdown/classes.md", import.meta.url), "utf8");

const CLASS_NAMES = [
  "Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Monk",
  "Paladin", "Ranger", "Rogue", "Sorcerer", "Warlock", "Wizard",
];

function classBlock(name, idx) {
  const heading = `\n## ${name}\n`;
  const start = text.indexOf(heading);
  const nextHeading = idx + 1 < CLASS_NAMES.length ? `\n## ${CLASS_NAMES[idx + 1]}\n` : null;
  const end = nextHeading ? text.indexOf(nextHeading) : text.length;
  return text.slice(start, end);
}

function parseKeyValueTable(block, caption) {
  const capIdx = block.indexOf(caption);
  const tableStart = block.indexOf("<table>", capIdx);
  const tableEnd = block.indexOf("</table>", tableStart) + "</table>".length;
  const table = block.slice(tableStart, tableEnd);
  const rows = [...table.matchAll(/<tr>([\s\S]*?)<\/tr>/g)];
  const result = {};
  for (const [, row] of rows) {
    const cells = [...row.matchAll(/<td>([\s\S]*?)<\/td>/g)].map((m) => m[1].trim());
    if (cells.length === 2) result[cells[0]] = cells[1];
  }
  return result;
}

function parseFeaturesTable(block, caption) {
  const capIdx = block.indexOf(caption);
  const tableStart = block.indexOf("<table>", capIdx);
  const tableEnd = block.indexOf("</table>", tableStart) + "</table>".length;
  const table = block.slice(tableStart, tableEnd);

  const theadMatch = table.match(/<thead>([\s\S]*?)<\/thead>/);
  const theadRows = [...theadMatch[1].matchAll(/<tr>([\s\S]*?)<\/tr>/g)].map(([, r]) => r);

  function rowCells(row) {
    return [...row.matchAll(/<th[^>]*>([\s\S]*?)<\/th>/g)].map((m) => ({
      text: m[1].replace(/\n/g, "").trim(),
      colspan: parseInt((m[0].match(/colspan="(\d+)"/) || [, "1"])[1], 10),
    }));
  }

  let headers;
  if (theadRows.length === 1) {
    headers = rowCells(theadRows[0]).flatMap((c) => Array(c.colspan).fill(c.text));
  } else {
    // Two-row header (spellcasting classes): expand row1 by colspan, then
    // combine with row2's per-column labels (spell slot level numbers).
    const row1Expanded = rowCells(theadRows[0]).flatMap((c) => Array(c.colspan).fill(c.text));
    const row2 = rowCells(theadRows[1]).map((c) => c.text);
    headers = row1Expanded.map((h, i) => (row2[i] ? row2[i] : h));
  }

  const bodyMatch = table.match(/<tbody>([\s\S]*?)<\/tbody>/);
  const rows = [...bodyMatch[1].matchAll(/<tr>([\s\S]*?)<\/tr>/g)];

  return rows.map(([, row]) => {
    const cells = [...row.matchAll(/<td>([\s\S]*?)<\/td>/g)].map((m) => m[1].trim());
    const record = {};
    const spellSlots = {};
    headers.forEach((h, i) => {
      const val = cells[i] === "—" || cells[i] === "" ? null : cells[i];
      if (/^\d+$/.test(h)) {
        spellSlots[h] = val;
      } else {
        record[h] = val;
      }
    });
    if (Object.keys(spellSlots).length) record.spellSlots = spellSlots;
    return record;
  });
}

function parseSpellListTable(part) {
  const tableStart = part.indexOf("<table>");
  const tableEnd = part.indexOf("</table>", tableStart) + "</table>".length;
  const table = part.slice(tableStart, tableEnd);
  const bodyMatch = table.match(/<tbody>([\s\S]*?)<\/tbody>/);
  return [...bodyMatch[1].matchAll(/<tr>([\s\S]*?)<\/tr>/g)].map(([, row]) => {
    const [spell, school, special] = [...row.matchAll(/<td>([\s\S]*?)<\/td>/g)].map((m) => m[1].trim());
    return { spell, school, special: special === "—" ? null : special };
  });
}

// Returns { features, spellsByLevel } - "#### Level N: Name" blocks are real
// class/subclass features; "#### Level N <Class> Spells" blocks are a
// reference table of that class's spell list at that spell level, not a
// feature, and are parsed separately.
function parseFeatureBlocks(sectionText) {
  const parts = sectionText.split(/\n#### Level /).slice(1);
  const features = [];
  const spellsByLevel = {};
  for (const part of parts) {
    const headerLine = part.slice(0, part.indexOf("\n"));
    const rest = part.slice(part.indexOf("\n") + 1).trim();

    const featureMatch = headerLine.match(/^(\d+):\s*(.+)/);
    if (featureMatch) {
      features.push({ level: parseInt(featureMatch[1], 10), name: featureMatch[2].trim(), desc: rest });
      continue;
    }

    const spellListMatch = headerLine.match(/^(\d+) .+ Spells$/);
    if (spellListMatch) {
      spellsByLevel[spellListMatch[1]] = parseSpellListTable(rest);
      continue;
    }

    console.log(`  (unrecognized heading, skipped: "Level ${headerLine}")`);
  }
  return { features, spellsByLevel };
}

const classes = CLASS_NAMES.map((name, idx) => {
  const block = classBlock(name, idx);

  const traits = parseKeyValueTable(block, `**Core ${name} Traits**`);
  const levels = parseFeaturesTable(block, `**${name} Features**`);

  const classFeaturesStart = block.indexOf(`### ${name} Class Features`);
  const subclassHeadingMatch = block.match(new RegExp(`\\n### ${name} Subclass: (.+)\\n`));
  const classFeaturesEnd = subclassHeadingMatch ? subclassHeadingMatch.index : block.length;
  const classFeaturesText = block.slice(classFeaturesStart, classFeaturesEnd);
  const { features, spellsByLevel } = parseFeatureBlocks(classFeaturesText);

  let subclass = null;
  if (subclassHeadingMatch) {
    const subclassName = subclassHeadingMatch[1].trim();
    const subclassStart = subclassHeadingMatch.index;
    const subclassText = block.slice(subclassStart);
    const subclassParsed = parseFeatureBlocks(subclassText);
    subclass = {
      key: `srd-2024_${subclassName.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-subclass`,
      name: subclassName,
      features: subclassParsed.features,
    };
  }

  return {
    key: `srd-2024_${name.toLowerCase()}-class`,
    name,
    traits,
    levels,
    features,
    spellsByLevel: Object.keys(spellsByLevel).length ? spellsByLevel : undefined,
    subclass,
    document: "srd-2024",
  };
});

console.log(
  classes
    .map(
      (c) =>
        `${c.name}: ${c.features.length} features, subclass "${c.subclass?.name}" (${c.subclass?.features.length} features), ${c.levels.length} level rows${c.spellsByLevel ? `, spell list levels: ${Object.keys(c.spellsByLevel).join(",")}` : ""}`
    )
    .join("\n")
);

await writeFile(new URL("../data/classes.json", import.meta.url), JSON.stringify(classes, null, 2));
