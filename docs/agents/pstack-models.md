# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` or `auto` runs the role on the parent chat model; omit the subagent model. Alias entries in panel lists count toward fan-out.
# budget: medium (high)
# Codex: pass reasoning_effort="high" separately for every real model below, including panel entries. Keep model names exactly as written. Aliases inherit the parent model and effort.
feature, refactoring: gpt-6.1-sol
bug-fix: gpt-6.1-sol
perf-issue: gpt-6.1-sol
hillclimb: gpt-6.1-sol
judgment and prose: gpt-6-astra
hardest tasks: gpt-6-astra
how explorer: gpt-6.1-sol
how explainer: gpt-6-astra
why investigators: gpt-6.1-sol
why synthesizer: gpt-6-astra
reflect tooling: gpt-6.1-sol
reflect judgment, divergent, synthesizer: gpt-6-astra
arena runners: gpt-6-astra, gpt-6.1-sol, gpt-6-sol, gpt-5.6-sol
arena cross-judge pool: gpt-6-astra, gpt-6.1-sol, gpt-6-sol, gpt-5.6-sol
swarm workers: gpt-6.1-sol
architect runners: gpt-6-astra, gpt-6.1-sol, gpt-6-sol, gpt-5.6-sol
interrogate reviewers: gpt-6-astra, gpt-6.1-sol, gpt-6-sol, gpt-5.6-sol
