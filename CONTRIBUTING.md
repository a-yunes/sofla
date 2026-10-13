# Contributing

Keep changes focused. Describe the behavior, add regression coverage, and explain validation.
Follow [design.md](design.md). Preserve the classic Launchpad feel and measure performance-sensitive
changes in Release, including responsiveness, memory, idle CPU, and app size. Fix regressions before merging.
Use synthetic app fixtures. Never include personal files, inventories, or credentials.

```sh
./scripts/check.sh
./scripts/test-native-regressions.py
./scripts/test-ui.sh
```

UI checks need a logged-in desktop session. Benchmark optimized builds with
`./scripts/benchmark.py`. See [AGENTS.md](AGENTS.md) for architecture and safety rules.

Contributions are accepted under the MIT license. Be kind and constructive.
