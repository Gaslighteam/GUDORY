# GUDORY — concept supplement (theme: 감각 / sense)

Built on Bomin's original concept doc. Three things were adjusted: the link to the theme "sense", the constraints of 24 hours and 4 people, and the judging rubric.
The core ideas stay: one instruction at a time, body-relative wording, hand-over mode, deciding who should move.

## 0. Summary
1. **Theme link:** the word "sense" never appeared in the original doc. This app turns the owner's **visual sense (an eye for composition)** into the **bodily senses** the photographer can act on (sound, vibration, steps, hand height). That is the identity.
2. **AI framing:** writing "no generative AI" costs points on the 20-point technical criterion. Lead with the fact that the core loop is **on-device vision AI** (pose estimation + person segmentation + CLIP scene understanding). The LLM is added as **"instruction text in any language, generated on demand"**.
3. **MVP cut:** four axes only (level, distance, horizontal, height), Korean plus LLM translations, no account or cloud.
4. **The demo video decides it:** no live demo is allowed, so the video must show "someone who does not care about photos gets the shot in three instructions, by sound alone".

---

## 1. Link to the theme "sense"

### Revised one-liner
> **You don't need a photographer's sense.** GUDORY turns the sense behind the photo you want into instructions the person holding your phone can follow **with ears, hands and feet**.

### Sense translation table (one slide)
| What the owner has | Sense delivered to the photographer | Implementation |
|---|---|---|
| "This angle is pretty" (visual sense) | **Hearing:** "one step back, please" voice | TTS |
| "Almost there" | **Hearing:** beeps that speed up as you get closer (parking-sensor style) | audio player |
| "Now!" | **Touch:** vibration the moment it matches | haptics |
| "A bit lower" | **Body sense:** "one fist lower", "half a step right" | errors converted to cm and steps |
| The whole composition | **Sight:** one sentence in the middle of the screen | hand-over mode |

- First-screen copy such as **"사진 감각, 빌려드릴게요"** puts the theme keyword on the first screen (10 points for theme fit).
- Candidate first sentence for the 500-char intro: "What the person you hand your phone to lacks is not skill — it is **sense**."

### Added device: feeling distance through sound
Photographers look at the subject more than at the screen (the original doc's own point). So beep intervals shorten as the target gets closer, and a continuous tone + vibration + auto capture fires when it matches. You can align without looking at the screen; it ties directly to the theme and makes a "wow" moment in the video.

---

## 2. AI roles (for the 20-point "technical excellence" criterion)

| AI | What it does | Without it |
|---|---|---|
| **Vision AI ① pose estimation** | extracts 33 joints from the reference and the live frame → person size and position | the service does not exist |
| **Vision AI ② person segmentation** | removes the person so the background alone can be compared → **decides whether the camera or the person should move** | the key differentiator disappears |
| **Vision AI ③ CLIP scene understanding** | reads the background, assigns a category and hashtags, selects the per-category good composition; adapted with team-curated photos | no target without a reference |
| **LLM (Lablup DeepSeek)** | generates the full instruction set in the photographer's language at hand-over time (keeping body-relative amounts); cached | fixed ko/en/ja strings (fallback) |

- Talk line: "The AI **sees** (vision), **decides** what is wrong (rule engine), and **says it in that person's language and body words** (LLM)."
- The LLM is not in the real-time loop. Instructions must hold for 1.5 s and LLM latency is 1–3 s, so it is called once at hand-over.
- The Lablup key exposes only the text model `DeepSeek-V4.1-Flash-B300`. **No feature where the LLM looks at the photo.**

---

## 3. MVP definition

### Four axes
Fix order: **level → distance → horizontal → height**. Distance changes everything else, so it comes before height.

| Axis | Computation | Tolerance | Body conversion |
|---|---|---|---|
| Level | gravity roll, phone upright (pitch) | roll ±3°, pitch ±10° | "hold the phone upright" |
| Distance | person height ratio = (head~ankle) ÷ frame height | ±10% | height 1.65 m, ~63° FOV → distance (m) → 0.6 m = one step |
| Horizontal | person center x (+ background shift) | ±8% | frame width in m → "half a step / one step" |
| Height | person vertical position (hip y) | ±8% | 10 cm = "one fist", larger → "waist height / knee height" |

- Person not fully in frame: "please get the whole person in the frame"
- Error growing: "the other way"
- An instruction holds at least 1.5 s and is not changed while the error is shrinking

---

## 4. "Who should move" on device
1. Shrink the reference and live frame (~96 px wide), convert to grayscale edge images.
2. **Erase the person** with the segmentation mask → background only.
3. Slide the two backgrounds ±20 px to find the best overlap → **background shift (dx)**. 2–3 times per second is enough; plain Dart, no OpenCV.
4. Decision:
   - background OK + person position off → **subject moves** ("model, one step left")
   - background and person off in the same direction → **camera moves** ("one step right")
   - low match confidence (lighting or location differs) → **camera only** (fallback)

> Film the demo scene as "background matches but the model is standing in the wrong place". This decision being visible is the proof of the differentiator.

---

## 5. Demo video storyboard (2 min 30 s)
| Time | Scene |
|---|---|
| 0:00–0:10 | **Hook:** the odd photo Mom took vs the reference. Caption "사진 감각, 빌려드릴게요" |
| 0:10–0:35 | Owner picks a reference → analysis screen with joint dots → hand over → language choice |
| 0:35–1:40 | **Split screen:** left the phone recording, right an outside shot of the photographer. "phone upright" → "two steps back" → **"model, one step left"** → beeps speed up → vibration + auto capture |
| 1:40–2:00 | Side-by-side result. Numbers such as "4 instructions, 23 seconds" |
| 2:00–2:30 | One more take with a foreigner (or another team's participant) in English. The photographer-language feature |

Needs: **an Android phone** (vibration), **reference photos we shot ourselves** (no Instagram photos — copyright), a second phone for the outside shot, a real photographer who does not care about photos (another team's participant or staff is most convincing).

---

## 6. Additional risks
| Risk | Response |
|---|---|
| Pose detection fails indoors / against the light | "get the whole person in frame" prompt; fix a bright demo location in advance |
| Background match misjudges | low confidence → camera-only guidance (fallback) |
| Instructions keep changing | 1.5 s hold + hysteresis (aligned at 1.0, misaligned again at 1.3) |
| Model loading is slow | preload on the owner's screen; no loading in hand-over mode |

## 7. Extra Q&A
| Question | Answer | Who |
|---|---|---|
| How is this different from Pixel's Camera Coach? | That suggests generic composition to the phone owner. We make **someone else** reproduce **the reference I chose**, and we instruct **the subject** too. (Check the Pixel feature before the talk.) | Eungyu |
| Does the photo go to a server? | No. Analysis and capture happen on the phone; the LLM only receives instruction templates. | Taeho |
| Why these models? | Pose and segmentation are ML Kit on device; CLIP is MIT-licensed and adapted with our own photos; the LLM is only for language. | Taeho |
