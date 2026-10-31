# Landscape diagnosis and preprocessing follow-up

Draft PR #37: https://github.com/Gaslighteam/GUDORY/pull/37.
Initial commit: `6073f7dc0ebf5e214b25478bce0d71c3159eaba0`.
The PR must remain Draft. This report supersedes the initial statement that no
successful landscape inference had been observed; older results are historical.

## Evidence and exclusions

The original log reported `selected=null`, incrementing embedding attempts and
generic `status=fallback`. That places the failure before cluster scoring but
cannot identify the swallowed exception retroactively. Do not label those old
events as proven CLIP failures or as a proven orientation defect.

The updated scalar diagnostics separate asset errors, no orientation clusters,
invalid orientation/crop, invalid camera layout, unavailable/empty/full masks,
empty crop masks, model loading, native CLIP failure, deadlines and busy jobs.
They do not expose camera pixels, mask arrays, embeddings or native file paths.

| Candidate cause | Evidence / result |
| --- | --- |
| Empty landscape clusters | Ruled out for this asset: 14 parsed landscape clusters. |
| Missing level data | Supported landscape cluster counts at levels 1–5 are 5, 7, 7, 8, 12. Exact levels 1/3/5 were selected on device. |
| Orientation selection mismatch | Both q=+1 and q=-1 were observed with landscape targets and successful native q8 matches. |
| Invalid preview crop | Standalone uses full frame. Geometry validation passed before embedding. Production preview-crop wiring remains a lead task. |
| Native CLIP/model failure | No such error was observed in the successful landscape run. Existing missing-model and invalid-tensor regression tests pass. |
| Rejected mask | Reproduced `fallback/mask/empty` with foreground 0/97200; these events terminate before CLIP. These particular instrumented events were portrait, so do not claim every prior landscape fallback had this cause. |

No shared camera, provider, core or orientation correction is justified by the
observed landscape results. The earlier lack of successful landscape evidence is
resolved for the indoor diagnostic, while the cause of each historical generic
fallback cannot be recovered from its insufficient logs.

## Physical indoor verification before the resize correction

SM-S937N / Android 16; one user-present indoor scene. Source 1440x1080 NV21,
sensor rotation 90, native mask 256x256. Native q8 inference, not a fake embedder.

| Held side | Level | f | h | cx | cy | Neighbors | Cosine | Total ms | Cached / embedding counter |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| +1 | 1 | chestUp | .374452 | .527680 | .445199 | 27 | .7076675851 | 3.699 | true / 15 |
| +1 | 3 | fullBody | .596341 | .513975 | .244213 | 7 | .7076675851 | .962 | true / 15 |
| +1 | 5 | fullBody | .379359 | .469959 | .346395 | 12 | .7076675851 | .665 | true / 15 |
| -1 | 1 | chestUp | .374485 | .527648 | .445188 | 27 | .7683570752 | 36.013 | true / 16 |
| -1 | 3 | fullBody | .596761 | .514267 | .243360 | 7 | .7683570752 | .829 | true / 16 |
| -1 | 5 | fullBody | .379481 | .470018 | .346338 | 12 | .7683570752 | 13.536 | true / 16 |

Corresponding fresh level-3 calls took 238.100 ms (+1) and 266.793 ms (-1),
with foreground 23097/97200 and 11990/97200. All hy were null. UI debug timing
is not a release performance guarantee. Framing changes explain why raw h must
not be compared as a global monotonic scale across levels.

## Confirmed Scene-owned preprocessing defect and correction

Controlled synthetic RGB inputs exposed a mismatch in the old Dart cubic resize:
the algorithm used a different coordinate/filter convention from Pillow's
training resize. This is a separate issue from proving the cause of the old
generic landscape fallback. Solid RGB normalization already agreed.

`clip_resize.dart` now provides the CLIP-only RGB resizer with matching pixel
centres, antialias support on reduction, normalized edge weights and per-pass
fixed-point rounding. Numerical behavior reference:
[Pillow RGB resampling](https://github.com/python-pillow/Pillow/blob/main/src/libImaging/Resample.c).
No Python, model, asset, dependency or camera-sampling changes were made. The
original native still-image fixture embedding remains unchanged.

Every probe compares all 150528 normalized values:

| Synthetic input | Old maximum absolute error | New maximum absolute error | New values differing by >1e-6 |
| --- | ---: | ---: | ---: |
| Pattern 16x12 (upsampling) | 2.686110437 | 0.000000238419 | 0 |
| Pattern 500x300 (downsampling) | 1.635307491 | 0.000000238419 | 0 |
| Constant RGB 30/100/220 | 0.000000119209 | 0.000000119209 | 0 |

Nine permanent synthetic RGB resize/crop goldens cover up/downsampling,
portrait/landscape, odd dimensions, an unchanged axis and single-pixel axes.
They compare every resulting RGB byte via FNV-1a and verify original pixels are
unchanged. `clip_parity_check.dart` also runs these references on the Android
diagnostic at startup, logging `SCENE PREPROCESS PARITY synthetic_rgb=9/9` on pass.
Float32 rounding accounts for the remaining <=2.39e-7 normalization difference.
This does not establish exact natural-image or full camera pipeline parity.

To reproduce references locally, generate synthetic pixels as
`R=(17*x+29*y)%256`, `G=(7*x*x+13*y)%256`, `B=(3*x+11*y*y)%256`.
Use the existing Python `background_clip.clip_pixels` for tensors. For RGB
goldens, Pillow BICUBIC resize the short side to 224, floor the other side,
centre crop using integer offsets, then FNV-1a RGB bytes (initial 2166136261,
multiply 16777619 modulo 2^32). No reference binary/cache is committed.

## Verification and remaining checkpoint

- 297 tests passed after the correction (75 Scene + 222 app), including all
  preserved tests, native q8 inference and ten new parity/mask regressions.
- Full Flutter analysis passed with no issues; the updated diagnostic Android
  APK built successfully. All 297 tests passed again after sharing the parity
  fixture gate between tests and the diagnostic.
- The corrected APK passed `SCENE PREPROCESS PARITY synthetic_rgb=9/9` on the
  physical SM-S937N / Android 16. Repeated indoor inference after the resize
  correction and street/open-sky quality at levels
  1/3/5 have not been observed and require the user's physical participation.
- Full end-to-end Android/Python parity remains unverified: Android uses the
  preserved stride-4 NV21 sampling, while training starts from full RGB photos;
  native segmentation/model inputs can also differ. The RGB resize gate does
  not waive those differences.

**팀장 요청:** wire the production Recommender provider, held direction,
portrait-preview crop and lifecycle/zoom cache invalidation. Confirm the shared
sampling policy and natural-image parity acceptance criteria with Tools before
claiming full training/runtime parity. No shared files or independent Tools
drafts were changed. Keep this PR Draft, unmerged and not ready for review.
