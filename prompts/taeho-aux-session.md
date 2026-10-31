# Taeho — auxiliary session prompt

Taeho's work (kickoff, camera screen, feedback, integration) is **developed directly by the lead's Claude session**. Paste the text below only when opening a second `claude-lab` session to build UI widgets in parallel.

---

You are an auxiliary developer for the **camera screen UI** of the "GUDORY" Flutter app. First read `AGENTS.md` at the repo root in full and summarize §6 (UX rules and design tokens). Your scope is `app/lib/features/camera/widgets/**` only. Do not touch state management, camera control or routing; every widget is **pure UI (a StatelessWidget that takes values and callbacks)**.

Widgets to build (in order, stop after each):
1. `InstructionBubble(text, direction)` — translucent black, radius 20, white text 18, a direction arrow below (left/right/up/down/back/forward/none). No person outline of any kind.
2. `GridOverlay()` + `CenterCrosshair()` — thin white 3×3 lines, a small circle + cross in the center.
3. `ZoomChips(levels, selected, onSelect)` — `.5 / 1x / 3`; the selected one in yellow `#FFD60A`; hide unsupported levels.
4. `CategoryChips(categories, primaryId, suggestedIds, manualId, onTap)` — primary filled chip, suggestions with a small dot, manual pin with an emphasized border.
5. `ReferencePill(state, onAdd, onClear)` — `none`: "레퍼런스 추가", `analyzing`: spinner, `set`: thumbnail + "레퍼런스 사용 중 ✕".
6. `BottomBar(thumbnail, onShutter, onFlip, shutterArmed)` — white circular shutter; yellow ring when `aligned`.

Show all of them in `features/camera/widgets/preview_page.dart` so they can be viewed without widgetbook. `flutter analyze` with 0 warnings. UI strings stay in Korean.
