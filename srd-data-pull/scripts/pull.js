// One-time pull of Open5e's structured SRD 5.2.1 (2024 rules) data.
// Run with: node pull.js
//
// IMPORTANT: after cross-checking Open5e's data against the actual SRD 5.2.1
// text, we found real gaps and contamination (see notes below) and switched
// to hand-parsing the SRD markdown directly for all real game content - see
// the other parse-*.js scripts and ../data/*.json. This script still pulls
// two kinds of data:
//   - GLOBAL_TABLES + METADATA: small reference tables verified unchanged
//     since 2014, and attribution metadata. These ARE the source of truth
//     for ../data/reference/.
//   - DOCUMENT_SCOPED: kept only as a cross-check tool against the
//     hand-parsed data in ../data/ (e.g. to re-verify counts after an SRD
//     errata update) - written to ../data/_open5e-crosscheck/, NOT used as
//     a primary source.

const BASE = "https://api.open5e.com/v2";
const DATA_DIR = new URL("../data/", import.meta.url);
const REFERENCE_DIR = new URL("../data/reference/", import.meta.url);
const CROSSCHECK_DIR = new URL("../data/_open5e-crosscheck/", import.meta.url);

// Endpoints scoped to the SRD-2024 document. All superseded by hand-parsed
// equivalents in ../data/ (spells.json, classes.json, etc.) - kept here only
// for cross-checking, not as a source of truth.
const DOCUMENT_SCOPED = [
  "spells",
  "classes",
  "backgrounds",
  "feats",
  "species",
  "items",
  "weapons",
  "armor",
];

// Weapon properties (incl. 2024's Mastery properties) is the one Open5e
// document-scoped endpoint we DIDN'T re-derive by hand-parsing equipment.md
// (only the per-weapon property *names* were parsed, not each property's
// full rules text) - verified correct against the SRD text, so this one
// still IS the source of truth for ../data/weapon-properties.json.
const WEAPON_PROPERTIES_TRUSTED = ["weaponproperties"];

// NOTE: "conditions" is deliberately excluded. Open5e has no srd-2024-tagged
// condition entries at all (verified directly against the API) - the 2024
// rules changed several conditions mechanically (Exhaustion, Prone,
// Unconscious), so reusing the 2014 text here would be silently wrong.
// See parse-conditions.js, which hand-extracts the 15 current conditions
// from the official SRD 5.2.1 markdown text instead.

// NOTE: "languages" is also deliberately excluded, for the same reason.
// Open5e's "core" language data is 2014-era and is missing "Common Sign
// Language" (a real 2024 addition), plus it uses the old Standard/Exotic
// split rather than 2024's Standard/Rare split. Verified against the actual
// SRD 5.2.1 text - see parse-languages.js, which hand-extracts the 19
// current languages from character-creation.md instead.

// Reference/taxonomy tables filtered to the base "core" document, which
// carries content confirmed unchanged since 2014 (verified against the SRD
// 5.2.1 text directly: sizes, alignments, damage types, and spell schools
// all match exactly). Open5e also mixes in unrelated third-party systems
// (Level Up: Advanced 5e, Tome of Beasts) on these same endpoints when
// unfiltered, so we scope to "core" explicitly rather than leaving them open.
const GLOBAL_TABLES = [
  "abilities",
  "skills",
  "sizes",
  "alignments",
  "damagetypes",
  "spellschools",
];

// Metadata needed to build a correct attribution notice.
const METADATA = ["documents", "licenses"];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchAllPages(url) {
  const results = [];
  let next = url;
  let pageCount = 0;
  while (next) {
    const res = await fetch(next);
    if (!res.ok) {
      throw new Error(`${res.status} ${res.statusText} fetching ${next}`);
    }
    const body = await res.json();
    results.push(...body.results);
    next = body.next;
    pageCount++;
    if (next) await sleep(200); // be polite between paginated requests
  }
  return { results, pageCount };
}

function documentKeyOf(record) {
  return typeof record.document === "string" ? record.document : record.document?.key;
}

async function pullEndpoint(name, { documentKey }) {
  const qs = documentKey
    ? `?document__key=${documentKey}&limit=100`
    : `?limit=100`;
  const url = `${BASE}/${name}/${qs}`;
  const { results, pageCount } = await fetchAllPages(url);

  if (!documentKey) return { results, pageCount };

  // The server-side document__key filter is inconsistently honored across
  // endpoints (confirmed: "skills" ignores it entirely and still returns
  // third-party entries). Filter client-side against each record's own
  // document field so correctness doesn't depend on that.
  const filtered = results.filter((r) => documentKeyOf(r) === documentKey);
  if (filtered.length !== results.length) {
    console.log(
      `  (${name}: server filter let ${results.length - filtered.length} non-${documentKey} record(s) through, dropped client-side)`
    );
  }
  return { results: filtered, pageCount };
}

const FILENAME_OVERRIDES = { weaponproperties: "weapon-properties" };

async function main() {
  const fs = await import("node:fs/promises");
  await fs.mkdir(DATA_DIR, { recursive: true });
  await fs.mkdir(REFERENCE_DIR, { recursive: true });
  await fs.mkdir(CROSSCHECK_DIR, { recursive: true });

  const summary = [];

  for (const [group, names, documentKey, outDir] of [
    ["weapon properties (source of truth)", WEAPON_PROPERTIES_TRUSTED, "srd-2024", DATA_DIR],
    ["document-scoped (crosscheck only)", DOCUMENT_SCOPED, "srd-2024", CROSSCHECK_DIR],
    ["global tables (source of truth)", GLOBAL_TABLES, "core", REFERENCE_DIR],
    ["metadata (source of truth)", METADATA, null, REFERENCE_DIR],
  ]) {
    console.log(`\n== ${group} ==`);
    for (const name of names) {
      try {
        const { results, pageCount } = await pullEndpoint(name, { documentKey });
        const filePath = new URL(`${FILENAME_OVERRIDES[name] ?? name}.json`, outDir);
        await fs.writeFile(filePath, JSON.stringify(results, null, 2));
        console.log(`  ${name}: ${results.length} records (${pageCount} page(s))`);
        summary.push({ name, count: results.length });
      } catch (err) {
        console.log(`  ${name}: FAILED - ${err.message}`);
        summary.push({ name, count: null, error: err.message });
      }
      await sleep(200);
    }
  }

  console.log("\n== Summary ==");
  for (const s of summary) {
    console.log(`  ${s.name}: ${s.error ? "FAILED" : s.count}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
