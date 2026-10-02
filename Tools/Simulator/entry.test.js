const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { gunzipSync } = require('node:zlib');
const { test } = require('node:test');
const sim = require('./entry');

const root = path.join(__dirname, '../..');
sim.loadCards(gunzipSync(fs.readFileSync(path.join(root,
    'Sources/SimulatorRuntime/Resources/simulator-cards.json.gz'))).toString());
const fixture = JSON.parse(fs.readFileSync(path.join(root,
    'Tests/TavernEngineTests/Golden/Combat/full-game-turn-11.input.json'), 'utf8'));

function input(ruleset) {
    const result = JSON.parse(JSON.stringify(fixture));
    for (const side of [result.playerBoard, result.opponentBoard]) {
        Object.assign(side.player, {
            tavernTier: 1, hpLeft: 40, heroPowers: [], hand: [], secrets: [],
            trinkets: [], questEntities: [], questRewards: [], questRewardEntities: [], globalInfo: {},
        });
        side.board = [];
    }
    result.options.applyDamageCap = false;
    result.gameState.anomalies = [];
    delete result.gameState.anomalyDbfIds;
    result.gameState.validTribes = null;
    if (ruleset) result.gameState.ruleset = ruleset;
    return result;
}

function minion(cardId, id, attack, health) {
    const result = JSON.parse(JSON.stringify(fixture.playerBoard.board[0]));
    Object.assign(result, { cardId, entityId: id, attack, health, maxHealth: health,
        taunt: false, divineShield: false, poisonous: false, venomous: false, reborn: false,
        stealth: false, windfury: false, locked: false, enchantments: [], tags: {},
        scriptDataNum1: 0, scriptDataNum2: 0, scriptDataNum3: 0, scriptDataNum4: 0,
        scriptDataNum5: 0, scriptDataNum6: 0 });
    delete result.additionalCardDbfIds;
    return result;
}

const options = JSON.stringify({ numberOfSimulations: 8, maxAcceptableDuration: 600000,
    intermediateResults: 1, skipInfoLogs: true, includeOutcomeSamples: false });
function run(value) {
    const handle = sim.start(JSON.stringify(value), options);
    let result;
    do { result = JSON.parse(sim.step(handle)); } while (!result.done);
    assert.equal(result.simulations, 8);
    return result;
}

test('36.6.3 changes only Deity damage tiers and leaves legacy runs intact', () => {
    for (const cardId of ['BGFYM_000', 'BGFYM_000_G', 'BGFYM_011', 'BGFYM_011_G']) {
        const old = input(); old.playerBoard.board = [minion(cardId, 500, 10, 10)];
        const current = input('36.6.3'); current.playerBoard.board = old.playerBoard.board;
        assert.equal(run(old).averageDamageWon, 4);
        assert.equal(run(current).averageDamageWon, 2);
        assert.equal(run(old).averageDamageWon, 4, 'patch service must not mutate the legacy database');
    }
});

test('36.6.3 uses four deaths for an unset sigil counter and preserves observed remaining deaths', () => {
    for (const remaining of [0, 1, 2, 3, 4]) {
        const value = input('36.6.3');
        value.playerBoard.board = [1, 2, 3].map(i => minion('BG36_308', 500 + i, 0, 1));
        value.opponentBoard.board = [minion('BG36_308', 600, 1, 1000)];
        value.playerBoard.player.secrets = [{ entityId: 700, cardId: 'BG_OldGod',
            scriptDataNum1: remaining, scriptDataNum2: 10000, scriptDataNum3: 10000,
            scriptDataNum6: 0, tags: { '4914': 10000, '4915': 10000 } }];
        assert.equal(run(value).won, remaining >= 1 && remaining <= 3 ? 100 : 0);
        delete value.gameState.ruleset;
        assert.equal(run(value).won, remaining <= 3 ? 100 : 0);
    }
});

test('interleaved generators keep their own Deity tier database', () => {
    const legacy = input(); legacy.playerBoard.board = [minion('BGFYM_000', 500, 10, 10)];
    const current = input('36.6.3'); current.playerBoard.board = legacy.playerBoard.board;
    const handles = [sim.start(JSON.stringify(legacy), options), sim.start(JSON.stringify(current), options)];
    const results = [null, null];
    while (results.some(result => !result?.done)) {
        for (let i = 0; i < handles.length; i++) {
            if (!results[i]?.done) results[i] = JSON.parse(sim.step(handles[i]));
        }
    }
    assert.equal(results[0].averageDamageWon, 4);
    assert.equal(results[1].averageDamageWon, 2);
});
