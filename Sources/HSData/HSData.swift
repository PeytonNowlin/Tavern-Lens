// HSData: shared Hearthstone data.
//
// - HSEnumeration.swift: `HS.<Group>` enums generated at build time from HearthstoneJSON
//   enums.json (Tools/HSEnumsGenerator via Plugins/HSEnumsPlugin); PowerParser's GameTag
//   name tables come from the same generator
// - CardDB.swift: cards.json for one build
// - HearthstoneBuild.swift: the installed client's build number
// - CardDataStore.swift: card data pinned to the running build, downloaded once and cached
// - MinionPool.swift: the live minion pool (card data + HSReplay meta period + our override
//   file + per-game self-heal); MetaPeriod.swift and PoolOverrides.swift are its sources,
//   with the shipped copies in Resources/bg-pool
//
// Planned (see docs/spec/tavern-lens-v1.md): Firestone hero and build stats.
