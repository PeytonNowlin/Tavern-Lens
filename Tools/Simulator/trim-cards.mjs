// Trims Firestone's cards_enUS JSON to what the simulator reads (TavernSim.trimCards, the same
// function the app runs on a downloaded card DB) and writes it gzipped.
//
//   node Tools/Simulator/trim-cards.mjs <cards_enUS.json> <out.json.gz>
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import { gzipSync, gunzipSync } from 'node:zlib';

const require = createRequire(import.meta.url);
const { trimCards } = require('./entry.js');

const [input, output] = process.argv.slice(2);
if (!input || !output) {
    console.error('usage: trim-cards.mjs <cards_enUS.json[.gz]> <out.json.gz>');
    process.exit(2);
}
let raw = readFileSync(input);
if (raw[0] === 0x1f && raw[1] === 0x8b) raw = gunzipSync(raw);
const trimmed = trimCards(raw.toString('utf8'));
// mtime 0 in the gzip header (Node writes 0) keeps the output byte-identical for the same input.
writeFileSync(output, gzipSync(Buffer.from(trimmed), { level: 9 }));
console.log(`kept ${JSON.parse(trimmed).length} cards, ${trimmed.length} bytes -> ${output}`);
