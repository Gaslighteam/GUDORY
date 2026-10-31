// Dataset and model credits shown in 설정 → 오픈소스 · 데이터 라이선스 next to the
// package licenses. Keep in sync with README "Data and credits".
import 'package:flutter/foundation.dart';

const dataLicenses = <(String, String)>[
  (
    'Open Images V7 (recommender v1 training photos)',
    'Google LLC. Annotations: CC BY 4.0 '
        '(https://creativecommons.org/licenses/by/4.0/). Images: Flickr, '
        'listed as CC BY 2.0 (https://creativecommons.org/licenses/by/2.0/); '
        'per-photo authors are kept with the local copies. '
        'Used on our PCs for training only. The app contains aggregated '
        'statistics (recommend.json), no photos.',
  ),
  (
    'CADB, Composition Assessment DataBase (recommender v2 training photos)',
    'B. Zhang, L. Niu, L. Zhang. "Image Composition Assessment with '
        'Saliency-augmented Multi-pattern Pooling", BMVC 2021. Code and '
        'annotations: MIT License '
        '(https://github.com/bcmi/Image-Composition-Assessment-Dataset-CADB). '
        'Images come from AADB (S. Kong et al., ECCV 2016), sourced from '
        'Flickr; copyright stays with the photographers. Used on our PCs for '
        'training only. The app contains learned weights and aggregates '
        '(recommend_v2.json), no photos.',
  ),
  (
    'CLIP ViT-B/32 (background embedding)',
    'OpenAI, MIT License (https://github.com/openai/CLIP). ONNX export: '
        'Xenova/clip-vit-base-patch32 (https://huggingface.co/Xenova/clip-vit-base-patch32).',
  ),
  (
    'Team photos',
    'Taken by the team and by friends who gave permission for this project '
        'only. Not distributed; the app contains aggregates only.',
  ),
];

/// Adds [dataLicenses] to Flutter's license page (showLicensePage).
void registerDataLicenses() {
  LicenseRegistry.addLicense(
    () => Stream.fromIterable([
      for (final (name, text) in dataLicenses)
        LicenseEntryWithLineBreaks(['GUDORY data: $name'], text),
    ]),
  );
}
