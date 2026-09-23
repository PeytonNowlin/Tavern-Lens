// Entry point bundled (esbuild, IIFE) into Sources/SimulatorRuntime/Resources/bgs-simulator.js.
//
// It exposes one global, `TavernSim`, to the JavaScriptCore context the app runs it in:
//   loadCards(json)            -> number of cards loaded (Firestone's cards_enUS format)
//   start(inputJson)           -> a handle for one BgsBattleInfo simulation
//   step(handle)               -> JSON: the result so far, `done` once finished
//   cancel(handle)
//   trimCards(json)            -> JSON: only the cards and fields the simulator reads
//   versions                   -> the pinned package versions
//
// The app keeps nothing else in the context, so this file is the whole contract.
// Node runs it too (scripts/update-simulator.sh uses trimCards to refresh the pinned card data).

const sim = require('@firestone-hs/simulate-bgs-battle');
const { AllCardsService } = require('@firestone-hs/reference-data');
const { CardsData } = require('@firestone-hs/simulate-bgs-battle/dist/cards/cards-data');
const simPackage = require('@firestone-hs/simulate-bgs-battle/package.json');
const refPackage = require('@firestone-hs/reference-data/package.json');

let cards = null;
const cardsDataByKey = new Map();
const runs = new Map();
let nextHandle = 1;

// Fields the simulator and reference-data never read; dropping them keeps the card DB small.
const DROPPED_FIELDS = new Set([
    'audio', 'audio2', 'flavor', 'artist', 'text', 'faction', 'rarity', 'collectible', 'classes', 'playerClass',
    'howToEarn', 'howToEarnGolden', 'targetingArrowText', 'availableAsSignature', 'availableAsDiamond',
    'touristFor', 'mercenary', 'mercenaryRole', 'mercenaryAbility', 'mercenaryAbilityCooldown',
    'mercenaryEquipment', 'mercenaryPassiveAbility', 'additionalCosts',
]);
const BG_ID = /^(BG|TB_Bacon|TB_BaconShop|TB_BaconUps)/;

function isSimulatorCard(card) {
    return card.set === 'Battlegrounds' || BG_ID.test(card.id || '') || !!card.techLevel ||
        !!card.battlegroundsNormalDbfId || !!card.battlegroundsPremiumDbfId ||
        !!card.battlegroundsPutridicePool1 || !!card.battlegroundsPutridicePool2 ||
        card.id === 'CS2_122'; // the simulator probes this card to check a DB is loaded
}

function trimCards(json) {
    const all = typeof json === 'string' ? JSON.parse(json) : json;
    const kept = all.filter(isSimulatorCard).map((card) => {
        const out = {};
        for (const key of Object.keys(card)) {
            if (!DROPPED_FIELDS.has(key)) out[key] = card[key];
        }
        return out;
    });
    kept.sort((a, b) => (a.dbfId || 0) - (b.dbfId || 0));
    return JSON.stringify(kept);
}

function loadCards(json) {
    const service = new AllCardsService();
    service.initializeCardsDbFromCards(typeof json === 'string' ? JSON.parse(json) : json);
    sim.assignCards(service);
    cards = service;
    cardsDataByKey.clear();
    return service.getCards().length;
}

// CardsData.inititialize(validTribes, anomalies) must be called by the embedder;
// simulateBattle doesn't read the lobby's tribes itself.
function cardsDataFor(validTribes, anomalies) {
    const key = JSON.stringify([validTribes || null, anomalies || []]);
    let data = cardsDataByKey.get(key);
    if (!data) {
        data = new CardsData(cards, false);
        data.inititialize(validTribes, anomalies || []);
        cardsDataByKey.set(key, data);
    }
    return data;
}

function summary(result, done, elapsed) {
    if (!result) return { done, simulations: 0, elapsedMs: elapsed };
    return {
        done,
        simulations: result.won + result.tied + result.lost,
        elapsedMs: elapsed,
        won: result.wonPercent, tied: result.tiedPercent, lost: result.lostPercent,
        wonLethal: result.wonLethalPercent, lostLethal: result.lostLethalPercent,
        averageDamageWon: result.averageDamageWon, averageDamageLost: result.averageDamageLost,
        damageWonRange: result.damageWonRange, damageLostRange: result.damageLostRange,
    };
}

// Tavern Lens sends dbfIds where only the card DB knows the card ID: the lobby's anomaly
// (`gameState.anomalyDbfIds`) and Zilliax / Build-An-Undead parts (`additionalCardDbfIds`).
function resolveDbfIds(input) {
    const idOf = (dbfId) => cards.getCardFromDbfId(dbfId).id;
    const gameState = input.gameState = input.gameState || {};
    if (gameState.anomalyDbfIds) {
        gameState.anomalies = (gameState.anomalies || []).concat(gameState.anomalyDbfIds.map(idOf).filter(Boolean));
        delete gameState.anomalyDbfIds;
    }
    const sides = [input.playerBoard, input.opponentBoard, input.playerTeammateBoard, input.opponentTeammateBoard];
    for (const side of sides.filter(Boolean)) {
        for (const entity of (side.board || []).concat(side.player.hand || [])) {
            if (entity.additionalCardDbfIds) {
                const extra = entity.additionalCardDbfIds.map(idOf).filter((id) => id && id !== entity.cardId);
                if (extra.length) entity.additionalCards = extra;
                delete entity.additionalCardDbfIds;
            }
        }
    }
}

// `optionsJson` overrides `input.options` (the host's simulation budget).
function start(inputJson, optionsJson) {
    if (!cards) throw new Error('TavernSim: cards not loaded');
    const input = JSON.parse(inputJson);
    input.options = Object.assign(input.options || {}, optionsJson ? JSON.parse(optionsJson) : {});
    resolveDbfIds(input);
    const gameState = input.gameState;
    const data = cardsDataFor(gameState.validTribes, gameState.anomalies);
    const handle = nextHandle++;
    runs.set(handle, { generator: sim.simulateBattle(input, cards, data), last: null, t0: Date.now() });
    return handle;
}

function step(handle) {
    const run = runs.get(handle);
    if (!run) return JSON.stringify({ done: true, cancelled: true, simulations: 0 });
    const next = run.generator.next();
    const elapsed = Date.now() - run.t0;
    if (next.done) {
        runs.delete(handle);
        return JSON.stringify(summary(next.value || run.last, true, elapsed));
    }
    run.last = next.value;
    return JSON.stringify(summary(next.value, false, elapsed));
}

function cancel(handle) {
    const run = runs.get(handle);
    if (run) {
        runs.delete(handle);
        try { run.generator.return(); } catch (e) { /* already finished */ }
    }
}

globalThis.TavernSim = {
    loadCards, start, step, cancel, trimCards,
    versions: { simulator: simPackage.version, referenceData: refPackage.version },
};
if (typeof module !== 'undefined') module.exports = globalThis.TavernSim;
