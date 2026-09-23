// Bundles entry.js and the installed (pinned) simulator into one IIFE for JavaScriptCore,
// and writes the pin next to it. Run by scripts/update-simulator.sh; don't edit the output by hand.
//
//   node Tools/Simulator/build.mjs
import { build } from 'esbuild';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const resources = join(here, '../../Sources/SimulatorRuntime/Resources');
const pkg = (name) => JSON.parse(readFileSync(join(here, 'node_modules', name, 'package.json'), 'utf8'));

await build({
    entryPoints: [join(here, 'entry.js')],
    outfile: join(resources, 'bgs-simulator.js'),
    bundle: true,
    format: 'iife',
    platform: 'neutral',
    mainFields: ['main', 'module'],
    // Whitespace and syntax only: identifiers keep their names, as in the published package.
    minifyWhitespace: true,
    minifySyntax: true,
    legalComments: 'none',
    banner: { js: readFileSync(join(here, 'jsc-shims.js'), 'utf8') },
    logLevel: 'warning',
});

const pin = {
    simulator: pkg('@firestone-hs/simulate-bgs-battle').version,
    referenceData: pkg('@firestone-hs/reference-data').version,
    esbuild: pkg('esbuild').version,
};
writeFileSync(join(resources, 'bgs-simulator.pin.json'), JSON.stringify(pin, null, 2) + '\n');
console.log('bundled', pin);
