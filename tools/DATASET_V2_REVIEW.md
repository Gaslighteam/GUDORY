# Dataset v2 verification checkpoint

Approved expanded dataset asset for submission. Recommendation quality remains provisional pending device validation. Submission contains generated assets and aggregate documentation only; Scene work and its PR are unchanged.

## Import and original integrity

- Inspected before extraction: 5603 JPEGs, one README and one local attribution CSV.
- Added 4742 unique supplementary photos; skipped 861 existing SHA-256 duplicates regardless of filename. No within-delivery duplicates.
- Complete sources: 85 team photos (weight 3), 5518 supplementary photos (weight 1).
- All 861 prior originals passed byte-for-byte checks before import; the original 797 also match their original archive.
- All 5603 originals are unique by SHA-256, unchanged across both rebuilds and match the complete v2 archive.
- All 5603 photos and the archives remain ignored by Git. Hashes and per-photo evidence stayed in memory; no per-photo manifest/cache was written.
- Source EXIF-corrected orientations: 1568 portrait, 3662 landscape, 373 near-square. EXIF: 21 orientation-1, 11 orientation-6, 5571 absent.

## Verification

- 53 existing Tools tests passed; all 28 installed packages compatible. Python syntax/import checks passed.
- The 53-test working-tree run includes 51 committed tests and two preserved local importer draft tests. Those draft source/test changes are excluded from this asset-only submission.
- Two complete native runs recomputed pose, masks, CLIP, quintiles, clusters and fallback targets from the full dataset.
- JSON and aggregate report were byte-identical across runs. Strict schema, canonical serialization, int8 cluster encoding and all ten fallbacks passed.
- A further full native rebuild after synchronizing the Tools worktree with main reproduced both approved hashes. The 51 committed tests also passed independently with the committed importer loaded, preserving the local importer draft.
- Pre-submission Flutter analysis found no issues, and the Android debug APK build passed in the synchronized Tools worktree. These build checks do not establish real-device recommendation quality or Android/Python preprocessing parity.
- JSON size: 107,801 bytes; SHA-256 `75f3e9bc6c33c3536e4f04e7152ac9306582bd46a6b2f5cfa6a72f8c5a3c456c`.
- Aggregate report SHA-256 `a59c76a850827903adc51aeb208f31512291396cb39155857b4ab765c7210dd9`.
- Existing source drafts, prior aggregate review and both fixed baseline files were preserved. Scene branch HEAD and every Scene file were unchanged.
- Original 797-photo baseline is retained. This run explicitly uses recommendation_baseline_861.json for the requested comparison.

## Aggregate totals versus the 861-photo baseline

Metric | Previous 861-photo baseline | Current | Change
--- | ---: | ---: | ---:
processed | 861 | 5603 | +4742
pose_accepted | 588 | 3256 | +2668
clip_accepted | 584 | 3233 | +2649
portrait_photos | 238 | 1191 | +953
landscape_photos | 346 | 2042 | +1696
portrait_clusters | 8 | 43 | +35
landscape_clusters | 14 | 60 | +46
json_bytes | 23888 | 107801 | +83913

The new photos contributed 2668 pose-accepted and 2649 CLIP-accepted samples;
2093 new photos were rejected. Accepted team photos remain 44, supplementary
photos increased from 540 to 3189. Weights remain 3 and 1 respectively.

## Rejection comparison

Reason | Previous | Current | Change
--- | ---: | ---: | ---:
Ambiguous person count | 195 | 1850 | +1655
Pose-count mismatch | 51 | 334 | +283
Invalid measurements | 21 | 84 | +63
Person/pose-box mismatch | 6 | 75 | +69
Missing required landmarks | 0 | 1 | +1
Square crop cuts person | 0 | 3 | +3
Segmentation rejection | 4 | 23 | +19
Total | 277 | 2370 | +2093

## Weighted person-scale boundaries

Orientation | Boundary | Previous | Current | Change
--- | ---: | ---: | ---: | ---:
portrait | 1 | 0.188838556 | 0.200942203 | +0.012103647
portrait | 2 | 0.134708047 | 0.138617411 | +0.003909364
portrait | 3 | 0.101605710 | 0.098668769 | -0.002936941
portrait | 4 | 0.073095739 | 0.069942176 | -0.003153563
landscape | 1 | 0.182417661 | 0.279123455 | +0.096705794
landscape | 2 | 0.122082576 | 0.173302040 | +0.051219463
landscape | 3 | 0.096482411 | 0.115825117 | +0.019342706
landscape | 4 | 0.071560934 | 0.075439967 | +0.003879033

## Five-level fallback comparison

Values are framing / h / shoulder-X / eye-Y / horizon. Different framing anchors make raw h deltas incomparable.

Orientation | Level | Previous | Current
--- | ---: | --- | ---
portrait | 1 | chestUp / 0.341517 / 0.516408 / 0.337558 / null | chestUp / 0.318325 / 0.525150 / 0.373748 / null
portrait | 2 | waistUp / 0.430069 / 0.521297 / 0.372651 / null | waistUp / 0.475461 / 0.522222 / 0.325517 / null
portrait | 3 | fullBody / 0.656590 / 0.505280 / 0.237168 / null | fullBody / 0.623722 / 0.506299 / 0.243319 / null
portrait | 4 | fullBody / 0.509820 / 0.497391 / 0.397028 / null | fullBody / 0.474386 / 0.497718 / 0.366446 / null
portrait | 5 | fullBody / 0.404394 / 0.485744 / 0.415191 / null | fullBody / 0.352599 / 0.514464 / 0.437597 / null
landscape | 1 | chestUp / 0.352778 / 0.513963 / 0.423609 / null | chestUp / 0.384527 / 0.511191 / 0.397119 / null
landscape | 2 | waistUp / 0.406718 / 0.502045 / 0.360510 / null | waistUp / 0.588717 / 0.505827 / 0.332259 / null
landscape | 3 | fullBody / 0.568365 / 0.534871 / 0.256488 / null | waistUp / 0.410475 / 0.486912 / 0.403431 / null
landscape | 4 | fullBody / 0.459652 / 0.559838 / 0.329139 / null | fullBody / 0.508129 / 0.511418 / 0.335048 / null
landscape | 5 | fullBody / 0.351169 / 0.482682 / 0.407283 / null | fullBody / 0.349607 / 0.493235 / 0.437628 / null

## Per-level distributions: previous and current

### Previous portrait

Level | Photos | Weighted mass | chestUp | waistUp | kneeUp | fullBody
--- | ---: | ---: | ---: | ---: | ---: | ---:
1 | 50 | 64 | 20 | 15 | 11 | 4
2 | 49 | 65 | 1 | 19 | 11 | 18
3 | 50 | 62 | 1 | 10 | 4 | 35
4 | 42 | 64 | 0 | 10 | 2 | 30
5 | 47 | 63 | 0 | 3 | 2 | 42

### Current portrait

Level | Photos | Weighted mass | chestUp | waistUp | kneeUp | fullBody
--- | ---: | ---: | ---: | ---: | ---: | ---:
1 | 249 | 255 | 123 | 88 | 32 | 6
2 | 238 | 254 | 18 | 82 | 65 | 73
3 | 234 | 254 | 5 | 47 | 30 | 152
4 | 230 | 254 | 1 | 33 | 22 | 174
5 | 240 | 254 | 3 | 35 | 13 | 189

### Previous landscape

Level | Photos | Weighted mass | chestUp | waistUp | kneeUp | fullBody
--- | ---: | ---: | ---: | ---: | ---: | ---:
1 | 71 | 71 | 36 | 25 | 7 | 3
2 | 69 | 71 | 3 | 26 | 16 | 24
3 | 69 | 71 | 0 | 16 | 11 | 42
4 | 67 | 71 | 0 | 15 | 10 | 42
5 | 70 | 70 | 0 | 12 | 7 | 51

### Current landscape

Level | Photos | Weighted mass | chestUp | waistUp | kneeUp | fullBody
--- | ---: | ---: | ---: | ---: | ---: | ---:
1 | 411 | 411 | 371 | 39 | 1 | 0
2 | 410 | 410 | 133 | 183 | 79 | 15
3 | 406 | 410 | 19 | 157 | 100 | 130
4 | 406 | 410 | 3 | 76 | 57 | 270
5 | 409 | 409 | 2 | 82 | 31 | 294

## Accepted framing totals

Framing | Previous | Current | Change
--- | ---: | ---: | ---:
chestUp | 61 | 678 | +617
waistUp | 151 | 822 | +671
kneeUp | 81 | 430 | +349
fullBody | 291 | 1303 | +1012

All ten fallbacks have direct level support without pooling. There are 303
supported cluster-level entries and 212 absent entries. Eleven portrait and three
landscape clusters without adequate level support were omitted; all accepted
samples still contribute to global quintiles and fallbacks.

## Limitations and review boundary

This is the existing verified Tools pipeline with unchanged models, thresholds, source weights, pose policy and preprocessing. No Scene resizer/model/integration changes were imported or made. Full camera/training preprocessing parity and human recommendation-quality checks are separate work.
Pose/person counting can miss hidden people. The present pose policy and curated one-person acceptance must still be assessed by humans; dataset consent/attribution remain local review duties.
No shared contracts, Flutter dependencies, Scene worktree or PRs were modified. No raw photos, original filenames, URLs, per-photo measurements/embeddings or model weights are included. Only aggregated centres and composition medians are exported. The generated recommendation asset remains provisional pending device quality and preprocessing-parity validation.

### Missing cluster levels

The schema intentionally omits unsupported `lv` keys instead of exporting empty compositions. Consumers must select supported same-orientation levels (nearest level when the requested level is absent) and use the orientation/level fallback when matching cannot produce a valid target. All ten global fallbacks are complete. Cluster centre bytes must be decoded as signed int8 and renormalized before cosine comparison.

### 팀장 요청: newer pose-policy alignment

Current main's AGENTS.md now permits estimated nose/eye coordinates regardless of visibility and always averages both eye Y coordinates, to retain back views and profiles. This approved asset was generated by the existing reviewed pipeline, which still requires a visible nose and uses the prior eye-visibility fallback rules. The JSON schema is current; training acceptance/head-reference semantics have not yet been aligned with that newer policy. Plan a separate Tools policy/test change and complete regeneration after team review. This asset-only submission deliberately preserves the approved measurements and counts.
