# Physical Android Recommender smoke verification

Update: successful indoor landscape matching in both directions was subsequently
observed. See `LANDSCAPE_DIAGNOSIS.md` for the later evidence and preprocessing
correction. The initial observations below remain a historical record.

Device: Samsung SM-S937N (S25 Edge), Android 16. Date: 2026-10-31 KST.
The standalone Recommender diagnostic debug APK was installed with `adb install
-r`, preserving existing app data. No training photos, camera frames, screenshots,
embeddings, device serials or personal paths were collected into this report.
Evidence below is aggregate target/scalar diagnostic output, not source-photo
measurements. The environment was one user-present scene, not a controlled
indoor/street/open-sky validation set.

## Verified on the phone

- App launch, rear camera stream and native ML Kit segmentation initialization.
- Actual portrait background masking -> native q8 CLIP -> same-orientation
  aggregate cluster matching. Positive cosine, `model=q8` and nonzero neighbor
  support were observed; initial fallback and later successful inference did
  not crash the screen.
- The first observed matched level-3 call took 1022.510 ms total. Subsequent
  uncached matched examples took about 149–258 ms. These include the whole
  debug-mode path, not isolated ONNX Run, and do not establish cold-install or
  release-build performance. One observed level-3 result had 17 contributors.
- A grouped portrait comparison reused the same normalized embedding. The
  embedding counter stayed **43** at all three levels; all reported
  `cached=true` and top cosine **0.7741437613**:

| Requested / selected | Framing | h | cx | cy | Contributors | Total ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 / 1 | waistUp | 0.551812 | 0.522222 | 0.324178 | 8 | 11.880 |
| 3 / 3 | fullBody | 0.636211 | 0.403270 | 0.222750 | 15 | 2.828 |
| 5 / 5 | fullBody | 0.380098 | 0.538381 | 0.361918 | 16 | 1.717 |

All horizons were null. Different framings use different span anchors; the
table is not evidence of a globally monotonic h requirement.

## Injected failure checks (separate from native matching)

- The diagnostic inference-failure switch produced a correct landscape level-3
  loaded-asset median (`h=0.568365`, `cx=0.534871`, `cy=0.256488`), neighbors 0,
  model none. This is a synchronous injected failure, not a native model crash.
- The missing-asset switch produced the embedded 797-photo landscape emergency
  medians at levels 1/3/5: chestUp h=0.364974, fullBody h=0.570680, fullBody
  h=0.343513. All had neighbors 0/model none, and the embedding counter stayed
  **63**. The loaded-asset median and emergency median were observably distinct.
- Both diagnostic switches were explicitly restored to off and their off states
  checked through Android accessibility text. No screenshot was used.

## Still pending

Actual successful native matching in both landscape directions, front-camera
mask alignment, preview-crop production wiring, repeated lifecycle behavior,
Android model-load failure with a deliberately missing-model build, natural-image
Python/Dart embedding parity and recommendation quality across indoor/street/open
sky. Top-right landscape was observed, but at that point ordinary requests were
returning safe fallbacks; that does not verify a successful landscape embedding.
The current scalar diagnostics do not distinguish every reason for an unavailable
embedding, so the cause must not be guessed from fallback alone.

Human perception of the proposed framing/position and three-background quality
review remain required. Automated tests and this smoke check do not replace them.

The user explicitly chose to finish the review with landscape device checks
pending. The diagnostic app was stopped and its temporary on-device accessibility
XML removed after testing. No source changes were made during device testing.
