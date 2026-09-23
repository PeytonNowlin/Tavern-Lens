# Third-party notices

Tavern Lens is MIT licensed (see [LICENSE](LICENSE)). It bundles or derives from the
following third-party software and data.

## Bundled software

`Sources/SimulatorRuntime/Resources/bgs-simulator.js` is built with esbuild
(`Tools/Simulator`) from these npm packages:

| Package | Version | License |
|---|---|---|
| [`@firestone-hs/simulate-bgs-battle`](https://www.npmjs.com/package/@firestone-hs/simulate-bgs-battle) | 1.1.755 | MIT |
| [`@firestone-hs/reference-data`](https://www.npmjs.com/package/@firestone-hs/reference-data) | 3.0.211 | MIT |

Both are published by the [Firestone](https://github.com/Zero-to-Heroes/firestone) project
(Zero to Heroes). The packages declare the MIT license in their `package.json` and ship no
separate license file or copyright line; the MIT terms below apply, with the copyright held by
their authors.

The bundle also contains esbuild's small runtime helpers.
[esbuild](https://github.com/evanw/esbuild) is MIT licensed, Copyright (c) 2020 Evan Wallace.

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Data

- **Card data and enums**: from [HearthstoneJSON](https://hearthstonejson.com/)
  (`Data/HearthstoneJSON`, `Tests/Fixtures/HearthstoneJSON`, and the simulator's trimmed card
  database). Card names, text and game data are © Blizzard Entertainment.
- **Hero statistics and build (comp) data**: from Firestone's public data
  (`Sources/HSData/Resources/bg-pool/builds`, `Tests/Fixtures/Firestone`).
- **Minion-pool metadata**: from [HSReplay](https://hsreplay.net/)
  (`Sources/HSData/Resources/bg-pool/hsreplay-meta-period-live.json`).
- **Hero-pick banner screenshot**: `Tests/Fixtures/Screen/hero-pick-banner-36.6.1.png`, a small
  crop of the game's screen used to test text recognition. © Blizzard Entertainment.

## Trademarks

Hearthstone, Battlegrounds and Blizzard Entertainment are trademarks or registered trademarks of
Blizzard Entertainment, Inc. Tavern Lens is not affiliated with or endorsed by Blizzard
Entertainment.
