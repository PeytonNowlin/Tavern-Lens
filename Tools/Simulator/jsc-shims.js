// Prepended to the bundle: what the simulator expects from Node that a bare JavaScriptCore context lacks.
// The host may define `console` first (to collect warnings); it's kept when present.
globalThis.process = globalThis.process || { env: {} };
globalThis.performance = globalThis.performance || { now: function () { return Date.now(); } };
globalThis.console = globalThis.console || {
    log: function () {}, info: function () {}, debug: function () {}, warn: function () {}, error: function () {},
    time: function () {}, timeEnd: function () {},
};
