# Recommendation data-generation report

Aggregate output only. No photo names, IDs, paths, measurements or per-photo embeddings.

Processed: 5603; pose accepted: 3256; background embeddings accepted: 3233; rejected: 2370.
Source weights: team 3; supplementary 1.
recommend.json: 107,801 bytes (limit < 1,000,000 bytes).

## Filters and source counts

Aggregate | Count
--- | ---:
accepted | 3233
accepted_source/supplementary | 3189
accepted_source/team | 44
pose_accepted | 3256
processed | 5603
rejected | 2370
rejected/pose/ambiguous_person_count | 1850
rejected/pose/invalid_measurements | 84
rejected/pose/missing_required_landmarks | 1
rejected/pose/person_pose_mismatch | 75
rejected/pose/pose_count_mismatch | 334
rejected/pose/square_crop_cuts_person | 3
rejected/segmentation | 23
source_orientation/landscape | 3662
source_orientation/near_square | 373
source_orientation/portrait | 1568

## portrait

Photos: 1191; weighted mass: 1271; exported clusters: 43; clusters without supported levels omitted: 11.

Level | Photos | Weighted mass | chestUp | waistUp | kneeUp | fullBody
--- | ---: | ---: | ---: | ---: | ---: | ---:
1 | 249 | 255 | 123 | 88 | 32 | 6
2 | 238 | 254 | 18 | 82 | 65 | 73
3 | 234 | 254 | 5 | 47 | 30 | 152
4 | 230 | 254 | 1 | 33 | 22 | 174
5 | 240 | 254 | 3 | 35 | 13 | 189

Cluster size (actual photos) | Number of clusters
--- | ---:
7 | 2
9 | 1
10 | 3
11 | 2
12 | 1
14 | 1
15 | 3
16 | 2
17 | 1
18 | 1
20 | 1
21 | 1
22 | 1
24 | 1
25 | 2
26 | 1
28 | 1
29 | 1
32 | 2
34 | 2
37 | 2
40 | 1
41 | 1
42 | 1
43 | 1
45 | 2
46 | 2
47 | 1
48 | 1
50 | 1

Fallback target level | Levels pooled (nearest first)
--- | ---
1 | 1
2 | 2
3 | 3
4 | 4
5 | 5

## landscape

Photos: 2042; weighted mass: 2050; exported clusters: 60; clusters without supported levels omitted: 3.

Level | Photos | Weighted mass | chestUp | waistUp | kneeUp | fullBody
--- | ---: | ---: | ---: | ---: | ---: | ---:
1 | 411 | 411 | 371 | 39 | 1 | 0
2 | 410 | 410 | 133 | 183 | 79 | 15
3 | 406 | 410 | 19 | 157 | 100 | 130
4 | 406 | 410 | 3 | 76 | 57 | 270
5 | 409 | 409 | 2 | 82 | 31 | 294

Cluster size (actual photos) | Number of clusters
--- | ---:
10 | 2
12 | 1
13 | 2
17 | 4
18 | 1
19 | 1
20 | 1
21 | 3
24 | 4
26 | 3
27 | 2
28 | 1
29 | 3
31 | 1
32 | 1
33 | 1
34 | 1
35 | 1
37 | 4
38 | 1
39 | 2
40 | 2
43 | 3
44 | 2
45 | 3
47 | 1
48 | 1
50 | 1
52 | 1
53 | 1
54 | 2
67 | 1
73 | 1
81 | 1

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

## Provisional asset and fixed baseline comparison

recommend.json is provisional and may be regenerated when more photos arrive.
Every run recursively discovers the full photo input and recomputes pose statistics,
embeddings, boundaries, clusters and fallbacks from scratch. Prior JSON/report
statistics are never loaded as training input. This baseline is read only for reporting.

Metric | Fixed baseline | Current | Change
--- | ---: | ---: | ---:
processed | 861 | 5603 | +4742
pose_accepted | 588 | 3256 | +2668
clip_accepted | 584 | 3233 | +2649
portrait_photos | 238 | 1191 | +953
landscape_photos | 346 | 2042 | +1696
portrait_clusters | 8 | 43 | +35
landscape_clusters | 14 | 60 | +46
json_bytes | 23888 | 107801 | +83913

Configuration matches fixed baseline: yes.
Aggregate asset SHA-256 matches fixed baseline: no.
The fixed baseline is never overwritten automatically. No photo IDs or per-photo history are stored.
