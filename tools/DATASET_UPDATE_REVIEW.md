# Updated dataset verification checkpoint

Reviewed provisional asset snapshot for submission. This change includes only
the recommendation asset and aggregate documentation; no Python or Dart source
changes, dependencies, photos or model weights are included.

## Import and integrity

- Archive inspected before extraction: 861 JPEGs plus two local documentation/attribution files.
- Newly imported: 64 unique team photos. Duplicates skipped by SHA-256: 797 (all already present).
- Current source totals: 85 team photos (weight 3), 776 supplementary photos (weight 1).
- Of the 64 new photos, 36 passed pose and CLIP; 28 were rejected (23 ambiguous person counts, 4 pose-count mismatches, 1 invalid measurement).
- New-photo EXIF audit: 57 portrait, 7 landscape, no near-square images after correction; EXIF orientation 1 on 21, orientation 6 on 7, absent on 36.
- All original 797 photos verified unchanged against their original archive; all 861 files unchanged across both rebuilds. Hashes were held in memory only.
- No original photos, attribution records, filenames, URLs, per-photo measurements or model weights are included in review outputs.

## Verification

- 53 automated tests passed in the Tools worktree (51 existing tests plus two local importer-draft tests); 28 installed packages compatible. The importer source/test/README drafts remain outside this asset submission.
- All 51 existing tests also passed with the committed importer implementation and tests loaded in memory, independently of the local drafts.
- Python syntax passed for all 13 Tools source files; seven pipeline module imports passed. Git diff whitespace checks passed.
- Submission checks: Flutter analysis passed with no issues and the debug APK build passed. Real-device recommendation and Android preprocessing parity remain unverified.
- Two complete native runs recomputed pose, masking, CLIP, quintiles, clusters and fallback targets from scratch.
- JSON and aggregate report are byte-identical across both runs; schema validation and all ten fallbacks passed.
- Current asset: 23,888 bytes; SHA-256 `baa49f324801e6dfd2ace43e4d5243845163222f8a1db7c596c5fbfdb4811e53`.
- The fixed 797-photo baseline is unchanged. See report.md for total deltas, rejection reasons, orientations, framing and level distributions.

## Accepted orientation and framing totals

Orientation | chestUp | waistUp | kneeUp | fullBody | Total
--- | ---: | ---: | ---: | ---: | ---:
portrait | 22 | 57 | 30 | 129 | 238
landscape | 39 | 94 | 51 | 162 | 346
current total | 61 | 151 | 81 | 291 | 584
previous total | 61 | 134 | 76 | 277 | 548
change | +0 | +17 | +5 | +14 | +36

## Five-level photo counts

Orientation | Levels 1 through 5, previous | Levels 1 through 5, current
--- | --- | ---
portrait | 39, 40, 39, 44, 44 | 50, 49, 50, 42, 47
landscape | 69, 68, 69, 68, 68 | 71, 69, 69, 67, 70

Current weighted masses are 64, 65, 62, 64, 63 in portrait and 71, 71, 71, 71, 70 in landscape. All ten fallbacks have direct level support without pooling. Exported cluster-level entries increased from 59 to 63; 47 unavailable entries are represented by absent keys.

## Weighted person-scale boundaries

Orientation | Boundary | Previous | Current | Change
--- | ---: | ---: | ---: | ---:
portrait | 1 | 0.199939527 | 0.188838556 | -0.011100970
portrait | 2 | 0.147442974 | 0.134708047 | -0.012734927
portrait | 3 | 0.113923140 | 0.101605710 | -0.012317430
portrait | 4 | 0.077117935 | 0.073095739 | -0.004022196
landscape | 1 | 0.183852687 | 0.182417661 | -0.001435027
landscape | 2 | 0.123188451 | 0.122082576 | -0.001105875
landscape | 3 | 0.097202808 | 0.096482411 | -0.000720397
landscape | 4 | 0.070769101 | 0.071560934 | +0.000791833

## Five-level fallback comparison

Values are aggregate framing/span/shoulder-X/eye-Y; horizon remains null.

Orientation | Level | Previous f / h / cx / cy | Current f / h / cx / cy
--- | ---: | --- | ---
portrait | 1 | chestUp / 0.341517 / 0.516408 / 0.337558 | chestUp / 0.341517 / 0.516408 / 0.337558
portrait | 2 | waistUp / 0.475461 / 0.529401 / 0.258464 | waistUp / 0.430069 / 0.521297 / 0.372651
portrait | 3 | fullBody / 0.695083 / 0.505280 / 0.210041 | fullBody / 0.656590 / 0.505280 / 0.237168
portrait | 4 | fullBody / 0.558974 / 0.497391 / 0.244615 | fullBody / 0.509820 / 0.497391 / 0.397028
portrait | 5 | fullBody / 0.394225 / 0.482405 / 0.352647 | fullBody / 0.404394 / 0.485744 / 0.415191
landscape | 1 | chestUp / 0.364974 / 0.513963 / 0.423609 | chestUp / 0.352778 / 0.513963 / 0.423609
landscape | 2 | waistUp / 0.422341 / 0.543761 / 0.331357 | waistUp / 0.406718 / 0.502045 / 0.360510
landscape | 3 | fullBody / 0.570680 / 0.535579 / 0.261289 | fullBody / 0.568365 / 0.534871 / 0.256488
landscape | 4 | fullBody / 0.466302 / 0.566759 / 0.331493 | fullBody / 0.459652 / 0.559838 / 0.329139
landscape | 5 | fullBody / 0.343513 / 0.472695 / 0.407283 | fullBody / 0.351169 / 0.482682 / 0.407283

## Previous five-level distributions

Preserved aggregate baseline for comparison with the current per-level tables in report.md.

### Previous portrait

Level | Photos | Weighted mass | chestUp | waistUp | kneeUp | fullBody
--- | ---: | ---: | ---: | ---: | ---: | ---:
1 | 39 | 45 | 19 | 10 | 8 | 2
2 | 40 | 44 | 2 | 15 | 11 | 12
3 | 39 | 45 | 0 | 7 | 4 | 28
4 | 44 | 44 | 1 | 9 | 2 | 32
5 | 44 | 44 | 0 | 3 | 0 | 41

### Previous landscape

Level | Photos | Weighted mass | chestUp | waistUp | kneeUp | fullBody
--- | ---: | ---: | ---: | ---: | ---: | ---:
1 | 69 | 69 | 34 | 25 | 7 | 3
2 | 68 | 68 | 5 | 24 | 16 | 23
3 | 69 | 69 | 0 | 16 | 10 | 43
4 | 68 | 68 | 0 | 13 | 12 | 43
5 | 68 | 68 | 0 | 12 | 6 | 50

## Remaining review

Human composition-quality, consent/attribution and Android preprocessing/embedding parity checks remain pending. Person detection cannot prove absence of an occluded or undetected second person. The archive README still describes 21 team photos, while its actual source folder now contains 85; source totals above come from inspected contents.

recommend.json remains provisional and may be regenerated after more photos arrive. No changes were made to pose formulas, masking, CLIP, clustering, schema, source weights, dependencies or the fixed baseline. Local importer drafts add explicit wrapper selection and optional content deduplication; they are preserved but are not part of this asset submission.
