# Hearthstone BG Companion

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues for `PeytonNowlin/Hearthstone-BG-Companion` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Build and test

- Command Line Tools only (no Xcode). Run tests with `scripts/test.sh`, never plain `swift test`: under the CLT it silently runs zero tests. Re-record goldens with `TAVERN_RECORD_GOLDENS=1 scripts/test.sh`.
- Build the app bundle with `scripts/bundle-app.sh`.
