# Bomin — categories and data guide (no AI prompt needed; one optional prompt at the end)

> ⚠️ **Outdated since the 2026-10-31 pivot** (no categories, hashtags or labels.csv; training data = Unsplash Lite). See `data/README.md` and `AGENTS.md`.

## Deliverables and deadlines
| Deadline | Deliverable | Hand to |
|---|---|---|
| **18:00** | 6 categories + ≤ 15 hashtags finalized (id, Korean label, 3 English description sentences each) | Seojun → `categories.json` |
| 18:30 | Everyone has dropped their own photos into the shared folder | folder link in team chat |
| 20:00 | Batch 1: ≥ 10 photos per category + `labels.csv` | into `data/`, tell Seojun |
| 23:30 | Batch 2 | |
| **01:00** | Final (20–40 per category) → Seojun runs the script → JSON frozen | no photos added after this |
| 01:00– | Slide deck, script, 500-char intro (**complete by 10:00 with only the video link missing**) | |
| 10:30– | QA on the stable build; photographer role in the 11:00 demo video; insert the video link into the slides at 11:30 | |

## 1. Category and hashtag design (18:00)
- The category is the **single place axis** shown on the chips. Proposal: `mountain 산`, `sea 바다`, `city 도시`, `sunset 노을`, `forest 숲`, **`indoor 실내`** (needed for venue/cafe demos). "Sunset" is not a place and overlaps with "sea", so decide whether it stays a category or becomes a hashtag. My recommendation: keep it as a category defined as "the sky is the main subject".
- Hashtags are the multi-label axis: light (`#역광 #노을빛 #흐린날 #야경`), composition (`#전신 #상반신 #뒷모습 #여백 #중앙 #로우앵글`), mood (`#시원한 #아늑한 #감성`). 15 at most.
- Write **3 English description sentences** per category and hashtag. CLIP is more accurate in English. Format: `a photo of a person standing on a beach`, `a woman looking at the sea from the shore`, `a portrait taken at a sandy beach with waves`. Include a person in the sentence.
- Hand-off format for Seojun:
  ```
  id | label | English sentence 1 | English sentence 2 | English sentence 3 | (categories) default hashtag ids
  ```

## 2. Collecting photos
- **Allowed:** photos team members took themselves (old travel photos included), photos taken during the contest.
- **Not allowed:** Instagram/Pinterest/search results, photos taken by others with unclear rights.
- Photos are not committed; **only number vectors** go into the repo, so faces are fine — skip any you are not comfortable with.
- Criteria (in priority order): portrait > one person > full body (head to ankles visible) > "a composition you think is good". Non-full-body photos still help CLIP, so include them (they are only excluded from composition stats).
- Target: 20–40 per category, 120–200 total. Shoot the thin categories (indoor, city) around the venue now.
- Put 3–5 demo reference photos in a separate folder (`data/demo_refs/`): bright, full body, a background with clear features.

## 3. Labeling (`data/labels.csv`)
Rename files as `<categoryId>_<n>.jpg` (e.g. `sea_001.jpg`), put them in `data/photos/`, fill the sheet below and save as UTF-8 CSV.

```
file,primary,hashtags,person_count,orientation,notes
sea_001.jpg,sea,backlight;fullbody;negative_space,1,portrait,
city_014.jpg,city,night;halfbody,1,portrait,overcast
```
- `hashtags` separated by `;`, using ids (not labels).
- `orientation`: `portrait` / `landscape`. `person_count`: a number. Skip photos with 2+ people where possible.

## 4. Running the script (once Seojun has written it)
From the repo root:
```
uv run tools/build_assets.py --photos data/photos --labels data/labels.csv --out app/assets
```
When done, open `tools/report.md`, check **per-category counts** and **top-1 accuracy**, and post just the numbers in the chat. For confused pairs (e.g. forest ↔ mountain), add photos or adjust the English sentences.

## 5. Straight into the slides
- Sense translation table (sight → hearing, touch, body), competitor comparison table, the "AI sees (pose, CLIP) → decides (rules) → says it in body words (LLM)" diagram, a data slide ("CLIP adapted per category with N photos the team chose").
- "감각" in the first sentence of the 500-char intro.

---

## (Optional) prompt for Claude — polishing English sentences and hashtags
> I am designing categories and hashtags for scene classification in a photo-composition coaching app. They will be used for CLIP zero-shot classification, so each item needs 3 English sentences describing a photo **with one person in it**. Look at my draft below and ① point out pairs that will be confused with each other, ② rewrite the sentences in CLIP prompt style ("a photo of …") as a table. Do not add new items.
> (paste the category/hashtag draft here)
