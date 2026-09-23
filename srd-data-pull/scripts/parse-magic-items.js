// Hand-parsed extraction of magic items from the official SRD 5.2.1
// markdown (magic-items.md, "Magic Items A-Z"). Same validation approach as
// spells: only keep a "#### Name" block if the line right after it is the
// "_Category, Rarity_" tag line - filters out any non-item headings without
// hardcoding a name list.
import { readFile, writeFile } from "node:fs/promises";

const text = await readFile(new URL("../source/srd-markdown/magic-items.md", import.meta.url), "utf8");

const section = text.slice(text.indexOf("## Magic Items A"));
const parts = section.split(/\n#### /).slice(1);

const items = [];
for (const part of parts) {
  const nlIdx = part.indexOf("\n");
  const name = part.slice(0, nlIdx).trim();
  const rest = part.slice(nlIdx + 1).trim();

  const lines = rest.split("\n");
  const tagLine = lines[0].trim();
  const tagMatch = tagLine.match(/^_(.+)_$/);
  if (!tagMatch) continue; // not an item (stray heading)

  // A few items (e.g. Ring of Animal Influence) transform the wearer into
  // or summon a creature, and its full stat block is embedded right in the
  // item's own description using the same "_Size Type, Alignment_" tag
  // shape as a real item's "_Category, Rarity_" tag. Real items are
  // followed by prose; stat blocks are followed by "**AC** ... **HP** ...".
  if (lines.slice(1).join("\n").trim().startsWith("**AC**")) continue;

  const tag = tagMatch[1];
  // Category is everything before the first top-level comma; rarity is the
  // rest. Some categories embed their own commas in parens (e.g. "Weapon
  // (Any Ammunition)"), so split only on a comma outside parens.
  let depth = 0,
    splitAt = -1;
  for (let i = 0; i < tag.length; i++) {
    if (tag[i] === "(") depth++;
    else if (tag[i] === ")") depth--;
    else if (tag[i] === "," && depth === 0) {
      splitAt = i;
      break;
    }
  }
  const category = splitAt === -1 ? tag.trim() : tag.slice(0, splitAt).trim();
  const rarity = splitAt === -1 ? null : tag.slice(splitAt + 1).trim();

  const desc = lines.slice(1).join("\n").trim();

  items.push({
    key: `srd-2024_${name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-magic-item`,
    name,
    category,
    rarity,
    desc,
    document: "srd-2024",
  });
}

console.log(`magic items: ${items.length}`);
const byRarity = {};
for (const i of items) byRarity[i.rarity ?? "(none)"] = (byRarity[i.rarity ?? "(none)"] ?? 0) + 1;
console.log("by rarity (top-level string, imperfect for compound rarities):", byRarity);

await writeFile(new URL("../data/magic-items.json", import.meta.url), JSON.stringify(items, null, 2));
