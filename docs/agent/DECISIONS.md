# Buddy — Design Decisions Log

| # | Decision | Reason |
|---|----------|--------|
| 1 | Use `ValueNotifier` + `ValueListenableBuilder` for state (no Provider/Riverpod) | Matches existing codebase pattern — minimal dependencies, simple reactive updates |
| 2 | SMS parsing stays entirely on-device | Google Play policy compliance; no server-side upload of SMS content |
| 3 | Existing users default to India/INR when no country is saved | Preserves exact current behavior for all live users; nothing breaks |
| 4 | Currency change only changes display symbol, does NOT convert amounts | Converting historical data would require exchange rates and could cause confusion; simpler to just update display |

*(More decisions will be added as tasks progress)*
