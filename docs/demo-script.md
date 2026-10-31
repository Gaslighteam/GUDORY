# GUDORY demo video: shot list (2:30 target, 3:00 max)

Shoot at **11:00–11:30 Sun**, at least 2 full takes. Upload unlisted to YouTube by 11:50.
The app has **no voice guidance**, so on-screen captions carry the story. Captions are in Korean, with an English line underneath (the judges are Korean; English keeps the hand-over scene readable).

## Layout
- **Split screen** for every coaching scene. **Left:** the phone's screen recording, with internal audio on so the beeps and ding are captured. **Right:** an outside camera showing the photographer and the model.
- Put the vibration on screen as a 📳 caption flash, since audio can't show it. Even better, film a close-up of the hand when it buzzes.
- Captions go at the bottom center of the full frame, never over the phone's instruction bubble.

## Shot list

| # | Time | Scene | Phone (left) | Outside (right) | Caption (KO / EN) |
|---|---|---|---|---|---|
| 1 | 0:00–0:10 | **Hook** | Two photos side by side. A: the "handed to a stranger" shot (head cut off, tilted, person tiny). B: the GUDORY shot of the same place. | — | 폰을 맡기면 늘 이렇게 나오죠. / Hand your phone over, get this. → 구도리가 있으면, 이렇게. / With GUDORY, this. |
| 2 | 0:10–0:18 | Title | App opens on "사진 감각, 빌려드릴게요". | Owner hands the phone to the photographer. | 사진 감각, 빌려드릴게요 — GUDORY / Lending you a sense for photos |
| 3 | 0:18–0:50 | **추천 mode + level change** | 추천 mode, bar at 3. Bubble e.g. "두 걸음 뒤로 가 주세요". Then the owner taps 1 (인물 중심), and the instruction changes to step closer. | Photographer follows: steps back, then forward. | 배경을 보고, 비슷한 사진들의 구도를 추천해요 / It reads the background and suggests how others framed it. → 1 인물 중심 ↔ 5 배경 중심 / 1 = person, 5 = background |
| 4 | 0:50–1:05 | **Aligned → press the shutter** | Beeps speed up → ding + yellow shutter ring, bubble "좋아요! 지금 셔터를 눌러 주세요" → photographer taps the shutter → toast. | Photographer stops; hand buzzes; thumb presses the shutter (close-up). | 가까워질수록 삐-삐 빨라지고 / Beeps speed up as it gets closer → 맞으면 띵 + 📳, 이제 셔터만 누르면 끝 / Ding, buzz: just press the shutter |
| 5 | 1:05–1:35 | **맞춤 mode with a reference** | Switch to 맞춤. Tap the reference slot and pick a demo reference (portrait). Bubble guides: "폰을 주먹 하나만큼 아래로 내려 주세요" → ding + yellow ring → photographer presses the shutter. | Photographer lowers the phone, shifts sideways, presses the shutter. | 이 사진처럼 찍고 싶다면, 레퍼런스 한 장이면 돼요 / Want it like this? One reference photo is enough. |
| 6 | 1:35–1:45 | Side by side (edit) | Reference and result next to each other (edited in post; the app has no result screen). | — | 레퍼런스 ↔ 결과 / Reference ↔ result |
| 7 | 1:45–2:10 | **Hand-over in English** | Owner taps ✋ and picks English. Guide: "Just follow the text on screen. Press the shutter when it lines up." Bubble: "Take one step to your left" → "Perfect! Press the shutter now" → photographer presses → "Done! Please hand the phone back." | Owner hands the phone to an English-speaking photographer; they follow and hand it back. | 외국인에게 부탁해도 OK — 한국어 · English · 日本語 / Works in their language too |
| 8 | 2:10–2:25 | **Landscape** | 맞춤 with a **landscape** reference. Bubble: "폰을 가로로 돌려 주세요". Phone turns; icons and bubble rotate in place; coaching continues → ding + yellow ring → shutter. | Photographer turns the phone sideways, presses the shutter. | 가로 사진도 — 폰을 돌리라고 먼저 알려줘요 / Landscape too — it tells you to turn the phone first |
| 9 | 2:25–2:40 | **Saved photos** | Gallery → GUDORY album: the portrait, custom and landscape shots at full resolution, exactly as previewed. | — | 화면에 보이던 그대로, 원본 화질로 저장 / Saved exactly as previewed, full resolution → 모든 AI는 폰 안에서 — 사진은 밖으로 나가지 않아요 / All AI runs on the phone. No photo leaves it. |
| 10 | 2:40–2:50 | Outro | Logo + APK QR / link. | Team waves. | GUDORY (구도리) · Team Gaslighteam · APK: (link) |

Cut order if the video runs long: shot 6, then shot 2 (merge the title into the hook), then shorten shot 3 to a single level change.

## Before the take
- [ ] **Release APK** from the 10:30 stable build, installed on the demo phone. CLIP model bundled: check that 추천 mode gives instructions that change with the background, not the same median everywhere.
- [ ] Demo phone: charged, Do Not Disturb on, notifications hidden, media volume high, vibration on, screen recording with internal audio set up.
- [ ] **Back camera** selected: the front camera is a plain camera with no coaching, so don't flip during the takes.
- [ ] **Reference photos** in the gallery (team members only, from `data/demo_refs/`): at least one portrait and one **landscape** reference, shot at the demo location.
- [ ] GUDORY album emptied of test shots, so shot 9 shows only the takes.
- [ ] Hook photos (shot 1): one bad "stranger" shot and one GUDORY shot of the same spot, taken beforehand.
- [ ] Bright location, plain background distinct from the reference spot (so 추천 vs 맞춤 look different). Avoid crowds: a second person in the frame breaks the one-person pose.

## People and props
| Role | Who | Notes |
|---|---|---|
| Owner | (team member) | Opens the app, switches modes and levels, hands the phone over |
| Model | (team member) | Stands still; same outfit across takes |
| Photographer (Korean) | someone who doesn't care about photos | Must only follow the bubble, no coaching from the team |
| Photographer (English) | (team member or friend) | For shot 7 |
| Outside camera operator | (team member) | Second phone on a tripod or gimbal, landscape 16:9 |
| Editor | (team member) | Split screen, captions, 📳 flashes, upload |

Props: demo phone, second phone + tripod/gimbal for the outside view, power bank, the printed caption list (this file) for the editor.
