"""Local-only background masking and CLIP ViT-B/32 image encoding."""
from pathlib import Path

import numpy as np
from PIL import Image

MEAN = np.array([0.48145466, 0.4578275, 0.40821073], dtype=np.float32)
STD = np.array([0.26862954, 0.26130258, 0.27577711], dtype=np.float32)
DIM = 512


class SegmentationFailure(ValueError):
    pass


def normalize_embedding(values):
    vector = np.asarray(values, dtype=np.float32)
    if vector.shape != (DIM,) or not np.isfinite(vector).all():
        raise ValueError("Expected 512 finite embedding values")
    norm = np.linalg.norm(vector.astype(np.float64))
    if not np.isfinite(norm) or norm <= 0:
        raise ValueError("Invalid embedding norm")
    return (vector / norm).astype(np.float32)


def clip_pixels(image: Image.Image):
    """Short-side 224, bicubic resize, centre crop, RGB float32 NCHW.

    Matches the app's floor-sized resize and integer centre-crop placement.
    Pillow and Dart use their own bicubic interpolation implementations; exact
    cross-runtime pixel/embedding parity on natural images remains a device QA.
    """
    rgb = image.convert("RGB")
    width, height = rgb.size
    scale = 224 / min(width, height)
    size = (224 if width <= height else int(width * scale),
            224 if height <= width else int(height * scale))
    resized = rgb.resize(size, Image.Resampling.BICUBIC)
    left, top = (size[0] - 224) // 2, (size[1] - 224) // 2
    pixels = np.asarray(resized.crop((left, top, left + 224, top + 224)), dtype=np.float32)
    pixels = (pixels / np.float32(255) - MEAN) / STD
    return np.ascontiguousarray(pixels.transpose(2, 0, 1)[None], dtype=np.float32)


def mask_person(image: Image.Image, mask):
    """Fill confidence >= .5 with rounded whole-shot RGB mean, before CLIP crop.

    Invalid/empty/full masks fail closed for training. Nearest-neighbour scaling
    handles lower-resolution mask grids. Never silently embed the original.
    """
    if mask is None:
        raise SegmentationFailure("No mask")
    try:
        values = np.asarray(mask, dtype=np.float32)
    except (TypeError, ValueError) as error:
        raise SegmentationFailure("Invalid confidence mask") from error
    if (values.ndim != 2 or min(values.shape) < 1 or not np.isfinite(values).all()
            or np.any(values < 0) or np.any(values > 1)):
        raise SegmentationFailure("Invalid confidence mask")
    if values.shape != (image.height, image.width):
        values = np.asarray(Image.fromarray(values).resize(image.size, Image.Resampling.NEAREST))
    foreground = values >= .5
    if not foreground.any() or foreground.all():
        raise SegmentationFailure("Mask has no foreground or no background")
    pixels = np.array(image.convert("RGB"), dtype=np.uint8, copy=True)
    mean = np.floor(pixels.mean(axis=(0, 1), dtype=np.float64) + .5).astype(np.uint8)
    pixels[foreground] = mean
    return Image.fromarray(pixels)


class SelfieSegmenter:
    def __init__(self, model_path: Path):
        import mediapipe as mp
        from mediapipe.tasks.python import BaseOptions, vision
        if not model_path.is_file():
            raise FileNotFoundError("Missing local selfie segmentation model")
        self.mp = mp
        self.detector = vision.ImageSegmenter.create_from_options(
            vision.ImageSegmenterOptions(
                base_options=BaseOptions(model_asset_path=str(model_path)),
                running_mode=vision.RunningMode.IMAGE,
                output_confidence_masks=True, output_category_mask=False))
        # The official two-class SelfieSegmenter declares background/person.
        labels = [label.lower() for label in self.detector.labels]
        if labels not in (["background", "person"], ["background", "selfie"], ["selfie"]):
            self.detector.close()
            raise ValueError("Expected a supported selfie model label layout")
        # Official square model currently exposes one sigmoid 'selfie' mask;
        # also support the documented two-class background/person layout.
        self.mask_count = len(labels)
        self.person_index = len(labels) - 1

    def __call__(self, image):
        try:
            data = np.ascontiguousarray(image.convert("RGB"), dtype=np.uint8)
            result = self.detector.segment(self.mp.Image(image_format=self.mp.ImageFormat.SRGB, data=data))
            if result.confidence_masks is None or len(result.confidence_masks) != self.mask_count:
                raise SegmentationFailure("Unexpected selfie confidence mask count")
            mask = np.array(result.confidence_masks[self.person_index].numpy_view(), copy=True)
            return mask[..., 0] if mask.ndim == 3 and mask.shape[-1] == 1 else mask
        except Exception as error:
            raise SegmentationFailure("Segmentation failed") from error

    def close(self):
        self.detector.close()


class ClipEncoder:
    def __init__(self, model_path: Path):
        import onnxruntime as ort
        if not model_path.is_file():
            raise FileNotFoundError("Missing local CLIP vision model")
        options = ort.SessionOptions()
        options.intra_op_num_threads = 2
        options.inter_op_num_threads = 1
        self.session = ort.InferenceSession(str(model_path), options, providers=["CPUExecutionProvider"])
        if ([i.name for i in self.session.get_inputs()] != ["pixel_values"]
                or [o.name for o in self.session.get_outputs()] != ["image_embeds"]
                or self.session.get_inputs()[0].type != "tensor(float)"):
            raise ValueError("Unexpected CLIP vision graph")

    def __call__(self, image):
        output = np.asarray(self.session.run(["image_embeds"], {"pixel_values": clip_pixels(image)})[0])
        if output.shape != (1, DIM):
            raise ValueError("Expected image_embeds [1,512]")
        return normalize_embedding(output[0])


def background_embedding(image, segmenter, encoder):
    try:
        mask = segmenter(image)
    except Exception as error:
        raise SegmentationFailure("Segmentation failed") from error
    with mask_person(image, mask) as filled:
        return normalize_embedding(encoder(filled))


NOT_REAL_PERSON = 0.85  # reviewed on Open Images samples, 2026-11-01


class PersonPrompts:
    """CLIP text embeddings of "real person" vs "painting/statue/poster/
    mannequin/mirror..." sentences (person_prompts.npz, see person_prompts.py)."""

    def __init__(self, path: Path):
        data = np.load(path)
        self.embeddings = np.asarray(data["emb"], dtype=np.float32)
        self.real = int(data["real"])
        if self.embeddings.shape[1:] != (DIM,) or not 0 < self.real < len(self.embeddings):
            raise ValueError("Unexpected person prompt embeddings")

    def not_real_probability(self, image, box, encoder) -> float:
        """Zero-shot probability that the main person (box padded by 10%) is not a
        real person. Uses the person crop: the whole frame flags real people
        standing in front of murals and statues."""
        width, height = image.size
        left, top = box.left * width, box.top * height
        right, bottom = box.right * width, box.bottom * height
        pad = .1 * max(right - left, bottom - top)
        rect = (max(0, int(left - pad)), max(0, int(top - pad)),
                min(width, int(right + pad)), min(height, int(bottom + pad)))
        if rect[2] - rect[0] < 8 or rect[3] - rect[1] < 8:
            return 0.0
        with image.crop(rect) as crop:
            logits = 100 * (self.embeddings @ encoder(crop)).astype(np.float64)
        p = np.exp(logits - logits.max())
        return float(p[self.real:].sum() / p.sum())
