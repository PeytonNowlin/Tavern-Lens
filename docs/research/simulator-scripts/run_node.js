const path = process.argv[2], fs = require('fs');
const sim = require('@firestone-hs/simulate-bgs-battle');
const { AllCardsService } = require('@firestone-hs/reference-data');
const { CardsData } = require('@firestone-hs/simulate-bgs-battle/dist/cards/cards-data');
const origWarn = console.warn; const warns = {}; console.warn = (...a) => { const k = String(a[0]).slice(0, 80); warns[k] = (warns[k] || 0) + 1; };
const cards = new AllCardsService();
cards.initializeCardsDbFromCards(JSON.parse(fs.readFileSync(process.env.CARDS)));
sim.assignCards(cards);
const input = JSON.parse(fs.readFileSync(path));
if (process.env.NOCAP) input.options.applyDamageCap = false;
const cd = new CardsData(cards, false);
cd.inititialize(input.gameState.validTribes, input.gameState.anomalies);
const t0 = Date.now();
const gen = sim.simulateBattle(input, cards, cd); let r; while (!(r = gen.next()).done) {}
const x = r.value;
console.log(JSON.stringify({ ms: Date.now() - t0, won: x.wonPercent, tied: x.tiedPercent, lost: x.lostPercent, lostLethal: x.lostLethalPercent, avgDmgWon: +x.averageDamageWon.toFixed(2), avgDmgLost: +x.averageDamageLost.toFixed(2), dmgLostRange: x.damageLostRange, n: x.won + x.lost + x.tied }));
console.log('warnings', JSON.stringify(warns));
