// Hand-parsed extraction of feats from the official SRD 5.2.1 markdown (feats.md).
import { readFile, writeFile } from "node:fs/promises";

const text = await readFile(new URL("../source/srd-markdown/feats.md", import.meta.url), "utf8");

const section = text.slice(text.indexOf("### Origin Feats"));
const parts = section.split(/\n#### /).slice(1);

const feats = parts.map((part) => {
  const newlineIdx = part.indexOf("\n");
  const name = part.slice(0, newlineIdx).trim();
  const rest = part.slice(newlineIdx + 1).trim();

  const categoryMatch = rest.match(/^_([^_]+)_\s*\n/);
  const categoryLine = categoryMatch ? categoryMatch[1] : "";
  const body = categoryMatch ? rest.slice(categoryMatch[0].length).trim() : rest;

  const prereqMatch = categoryLine.match(/^(.+?)\s*\(Prerequisite:\s*(.+)\)$/);
  const category = prereqMatch ? prereqMatch[1].trim() : categoryLine.trim();
  const prerequisite = prereqMatch ? prereqMatch[2].trim() : null;

  // Named sub-benefits (e.g. "_Two Cantrips._ ...") are optional - most
  // feats are a single paragraph, some (Magic Initiate, Alert) break into
  // several named parts the same way species traits do.
  const blocks = body.split(/\n_(?=[A-Z][^_]*\._)/).map((s) => s.trim()).filter(Boolean);
  const benefits = [];
  let intro = "";
  for (const block of blocks) {
    const m = block.match(/^_?([^_]+)\._\s*([\s\S]*)/);
    if (m) {
      benefits.push({ name: m[1].trim(), desc: m[2].trim() });
    } else {
      intro += (intro ? "\n\n" : "") + block;
    }
  }

  return {
    key: `srd-2024_${name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-feat`,
    name,
    category,
    prerequisite,
    desc: intro || null,
    benefits,
    document: "srd-2024",
  };
});

console.log(`feats: ${feats.length}`);
console.log(feats.map((f) => `${f.name} [${f.category}]${f.prerequisite ? ` (req: ${f.prerequisite})` : ""}`).join("\n"));

await writeFile(new URL("../data/feats.json", import.meta.url), JSON.stringify(feats, null, 2));
