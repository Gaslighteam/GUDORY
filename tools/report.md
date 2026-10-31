# Recommendation data-generation report

Aggregate output only. No photo names, IDs, paths, measurements or per-photo embeddings.

Processed: 797; pose accepted: 552; background embeddings accepted: 548; rejected: 249.
Source weights: team 3; supplementary 1.
recommend.json: 23,478 bytes (limit < 1,000,000 bytes).

## Filters and source counts

Aggregate | Count
--- | ---:
accepted | 548
accepted_source/supplementary | 540
accepted_source/team | 8
pose_accepted | 552
processed | 797
rejected | 249
rejected/pose/ambiguous_person_count | 172
rejected/pose/invalid_measurements | 20
rejected/pose/person_pose_mismatch | 6
rejected/pose/pose_count_mismatch | 47
rejected/segmentation | 4
source_orientation/landscape | 521
source_orientation/near_square | 52
source_orientation/portrait | 224

## portrait

Photos: 206; weighted mass: 222; exported clusters: 8; clusters without supported levels omitted: 1.

Level | Photos | Weighted mass | chestUp | waistUp | kneeUp | fullBody
--- | ---: | ---: | ---: | ---: | ---: | ---:
1 | 39 | 45 | 19 | 10 | 8 | 2
2 | 40 | 44 | 2 | 15 | 11 | 12
3 | 39 | 45 | 0 | 7 | 4 | 28
4 | 44 | 44 | 1 | 9 | 2 | 32
5 | 44 | 44 | 0 | 3 | 0 | 41

Cluster size (actual photos) | Number of clusters
--- | ---:
5 | 1
21 | 1
24 | 1
26 | 1
28 | 1
30 | 1
31 | 1
38 | 1

Fallback target level | Levels pooled (nearest first)
--- | ---
1 | 1
2 | 2
3 | 3
4 | 4
5 | 5

## landscape

Photos: 342; weighted mass: 342; exported clusters: 14; clusters without supported levels omitted: 3.

Level | Photos | Weighted mass | chestUp | waistUp | kneeUp | fullBody
--- | ---: | ---: | ---: | ---: | ---: | ---:
1 | 69 | 69 | 34 | 25 | 7 | 3
2 | 68 | 68 | 5 | 24 | 16 | 23
3 | 69 | 69 | 0 | 16 | 10 | 43
4 | 68 | 68 | 0 | 13 | 12 | 43
5 | 68 | 68 | 0 | 12 | 6 | 50

Cluster size (actual photos) | Number of clusters
--- | ---:
14 | 2
15 | 1
18 | 2
19 | 1
21 | 1
22 | 2
24 | 1
27 | 1
29 | 1
38 | 1
40 | 1

Fallback target level | Levels pooled (nearest first)
--- | ---
1 | 1
2 | 2
3 | 3
4 | 4
5 | 5

## Definitions and limitations

- Uses the verified pose pipeline and original-frame person-count evidence; near-square shot crops are recomputed from the same centre-crop rectangle.
- Person confidence >= 0.5 is filled with the rounded RGB mean of the whole shot before CLIP preprocessing. Missing/invalid/empty/full masks reject the photo, never fall back to an unmasked embedding.
- CLIP: verified local ViT-B/32 q8 ONNX, RGB short-side 224 bicubic resize, integer centre crop 224x224, float32 NCHW, exact AGENTS.md mean/std; L2-normalized finite 512-vectors.
- Pillow and Dart bicubic interpolation implementations may differ on natural images. End-to-end pixel/embedding parity and recommendation quality on Android remain unverified.
- Weighted quintiles use inverse empirical CDF at 0.8/0.6/0.4/0.2. Equal scales stay together; empty levels borrow the nearest levels within the same orientation until the dominant framing has at least three contributors.
- Levels rank head-to-shoulder scale s, not raw span h. Spans measured to different framing anchors are not comparable and are not forced to be monotonic across framing changes.
- Dominant framing uses source-weight mass; ties use chestUp, waistUp, kneeUp, fullBody order. All medians use source weights and only that framing's photos. No span mixing across framings.
- K-means uses source weights, seed 0, n_init=10, Lloyd and one numerical-library thread. Target k=min(64,max(1,floor(actual photos/20)),distinct vectors). Groups with fewer than three photos merge into the nearest centre. The approximately-20 target is an average, not a per-cluster minimum.
- Cluster n is actual photos. Per-level n is actual dominant-framing contributors; levels with fewer than three are omitted. No individual-photo centre is exported; unsupported clusters are omitted.
- Centres are L2-normalized, rounded after scaling by 127, int8 and base64 encoded. Dequantized centres should be renormalized before cosine comparison.
- No per-photo caches are written. Missing orientations/insufficient aggregate support or model setup errors abort generation before replacing the prior asset.
- Human accuracy/consent/attribution review and Dart consumer verification remain required. No training photos leave this PC; only aggregated assets and this report are outputs.

## Runtime and model provenance

Component | Version or SHA-256
--- | ---
CLIP model | 583fd1110a514667812fee7d684952aaf82a99b959760c8d7dca7e0ab9839299
Person detector model | 0720bf247bd76e6594ea28fa9c6f7c5242be774818997dbbeffc4da460c723bb
Pose model | 59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a
Python | 3.12.16
Segmentation model | 191ac9529ae506ee0beefa6b2c945a172dab9d07d1e802a290a4e4038226658b
mediapipe | 1.2.0
numpy | 2.5.4
onnxruntime | 1.31.1
pillow | 13.0.0
scikit-learn | 1.9.1

Model hashes identify local model files, never individual training photos.
