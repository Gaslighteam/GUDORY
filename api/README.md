# api/ — LLM proxy (Taeho, Should)

One Vercel function: `POST /api/instructions` `{ "lang": "en" }` → JSON of instruction sentences per key.
The Lablup key lives only in Vercel env vars (`LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL`), never in the app.
20 s timeout, per-language result cache, per-IP rate limit. On failure the app falls back to built-in ko/en/ja strings.
