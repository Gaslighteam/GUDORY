"""Regenerates person_prompts.npz: CLIP text embeddings for the "real person vs
painting/statue/poster/mannequin/mirror" filter in recommendation_pipeline.py.

Same model family as the app's vision_q8 (Xenova/clip-vit-base-patch32). Needs
two extra local-only files and one package, NOT part of the pipeline install:
  onnx/text_model_quantized.onnx -> text_q8.onnx, tokenizer.json (same HF repo)
  uv pip install tokenizers
Run inside the folder holding them: python person_prompts.py <out.npz>
"""
import sys
import numpy as np, onnxruntime as ort
from tokenizers import Tokenizer

REAL = ["a photo of a person", "a candid travel photo of a person", "a snapshot of a man",
        "a snapshot of a woman", "a portrait photo of a real person", "a selfie",
        "a photo of a person from behind"]
FAKE = ["a painting of a person", "a drawing of a person", "an illustration of a person",
        "a cartoon", "a poster with a person on it", "a billboard advertisement",
        "a magazine cover", "a mannequin", "a statue", "a sculpture of a person",
        "a reflection of a person in a mirror", "a 3d render of a person", "a doll",
        "a photo of a screen showing a person", "a mural on a wall"]

tok = Tokenizer.from_file("tokenizer.json")
s = ort.InferenceSession("text_q8.onnx", providers=["CPUExecutionProvider"])
print([(i.name, i.shape) for i in s.get_inputs()], [o.name for o in s.get_outputs()])
out = []
for text in REAL + FAKE:
    ids = tok.encode(text).ids[:77]
    feed = {"input_ids": np.array([ids + [49407] * (77 - len(ids))], dtype=np.int64)}
    if any(i.name == "attention_mask" for i in s.get_inputs()):
        feed["attention_mask"] = np.array([[1] * len(ids) + [0] * (77 - len(ids))], dtype=np.int64)
    e = s.run(["text_embeds"], feed)[0][0]
    out.append(e / np.linalg.norm(e))
np.savez(sys.argv[1] if len(sys.argv) > 1 else "person_prompts.npz", emb=np.stack(out), real=len(REAL), labels=np.array(REAL + FAKE))
print("saved", len(out))
