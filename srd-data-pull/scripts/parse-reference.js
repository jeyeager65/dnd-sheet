// Small reference tables from the SRD 5.2.1 markdown: the six abilities,
// the 18 skills, damage types, the nine alignments, schools of magic,
// creature sizes, and weapon (and mastery) properties. Each comes from one
// table or bold-lead-in list in the SRD text:
//   abilities     playing-the-game.md  "Ability Descriptions" table
//   skills        playing-the-game.md  "Skills" table
//   sizes         playing-the-game.md  "Creature Size and Space" table
//   damagetypes   rules-glossary.md    "Damage Types" table
//   alignments    character-creation.md "The Nine Alignments"
//   spellschools  spells.md            "Schools of Magic" table
//   weapon-properties  equipment.md    "Properties" / "Mastery Properties"
import { readFile, writeFile, mkdir } from "node:fs/promises";

const read = (file) =>
  readFile(new URL(`../source/srd-markdown/${file}`, import.meta.url), "utf8");

const ABILITY_KEYS = {
  Strength: "str",
  Dexterity: "dex",
  Constitution: "con",
  Intelligence: "int",
  Wisdom: "wis",
  Charisma: "cha",
};

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");

// The body rows of the first <table> after the bold caption "**[caption]**",
// each as an array of cell texts.
function tableRows(text, caption) {
  const start = text.indexOf(`**${caption}**`);
  if (start === -1) throw new Error(`No "${caption}" table`);
  const tbody = text.slice(text.indexOf("<tbody>", start), text.indexOf("</tbody>", start));
  return [...tbody.matchAll(/<tr>([\s\S]*?)<\/tr>/g)].map((row) =>
    [...row[1].matchAll(/<td>([\s\S]*?)<\/td>/g)].map((cell) => cell[1].trim())
  );
}

// "**Name.** text" paragraphs between two headings (the name may sit on its
// own line, as Ammunition's does).
function boldLeadIns(text, fromHeading, toHeading) {
  const start = text.indexOf(fromHeading);
  const end = text.indexOf(toHeading, start + fromHeading.length);
  const section = text.slice(start, end);
  return [...section.matchAll(/\*\*([^*]+?)\.\*\*\s*([\s\S]*?)(?=\n\n\*\*|\n\n>|\n\n#|$)/g)].map(
    (m) => ({ name: m[1].trim(), desc: m[2].trim() })
  );
}

const playing = await read("playing-the-game.md");
const glossary = await read("rules-glossary.md");
const creation = await read("character-creation.md");
const spells = await read("spells.md");
const equipment = await read("equipment.md");

const abilities = tableRows(playing, "Ability Descriptions").map(([name, desc]) => ({
  key: ABILITY_KEYS[name],
  name,
  desc,
}));

const skills = tableRows(playing, "Skills").map(([name, ability, desc]) => ({
  key: slug(name),
  name,
  ability: ABILITY_KEYS[ability],
  desc,
}));

const sizes = tableRows(playing, "Creature Size and Space").map(([name, space, squares]) => ({
  key: slug(name),
  name,
  space,
  squares,
}));

const damageTypes = tableRows(glossary, "Damage Types").map(([name, desc]) => ({
  key: slug(name),
  name,
  desc,
}));

const alignmentSection = creation.slice(
  creation.indexOf("#### The Nine Alignments"),
  creation.indexOf("### Step 5")
);
const alignments = [
  ...alignmentSection.matchAll(/^_([A-Za-z ]+) \(([A-Z]{1,2})\)\._ (.+)$/gm),
].map(([, name, shortName, desc]) => ({ key: slug(name), name, shortName, desc }));

const spellSchools = tableRows(spells, "Schools of Magic").map(([name, desc]) => ({
  key: slug(name),
  name,
  desc,
}));

const weaponProperties = [
  ...boldLeadIns(equipment, "### Properties", "### Mastery Properties").map((p) => ({
    ...p,
    type: "Property",
  })),
  ...boldLeadIns(equipment, "### Mastery Properties", "**Weapons**").map((p) => ({
    ...p,
    type: "Mastery",
  })),
].map((p) => ({ key: slug(p.name), ...p }));

const expect = (label, list, count) => {
  if (list.length !== count) throw new Error(`${label}: expected ${count}, got ${list.length}`);
  if (list.some((e) => Object.values(e).some((v) => v === undefined || v === ""))) {
    throw new Error(`${label}: an entry has an empty field`);
  }
  console.log(`${label}: ${list.length}`);
};
expect("abilities", abilities, 6);
expect("skills", skills, 18);
expect("sizes", sizes, 6);
expect("damage types", damageTypes, 13);
expect("alignments", alignments, 9);
expect("spell schools", spellSchools, 8);
expect("weapon properties", weaponProperties, 18);

const out = (file, data) =>
  writeFile(new URL(`../data/${file}`, import.meta.url), JSON.stringify(data, null, 2) + "\n");
await mkdir(new URL("../data/reference/", import.meta.url), { recursive: true });
await out("reference/abilities.json", abilities);
await out("reference/skills.json", skills);
await out("reference/sizes.json", sizes);
await out("reference/damagetypes.json", damageTypes);
await out("reference/alignments.json", alignments);
await out("reference/spellschools.json", spellSchools);
await out("weapon-properties.json", weaponProperties);
