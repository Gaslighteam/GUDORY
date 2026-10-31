# data/ — curated good photos per category (Bomin)

- `photos/` originals. **Not committed** (.gitignore). File names `<categoryId>_<n>.jpg` (e.g. `sea_001.jpg`)
- `demo_refs/` 3–5 reference photos for the demo video. Not committed. Samples that ship in the app go to `app/assets/demo/` (lead)
- `labels.csv` labels. **The only file committed here**

## labels.csv
```
file,primary,hashtags,person_count,orientation,notes
sea_001.jpg,sea,backlight;fullbody;negative_space,1,portrait,
```
- `primary`: one category id from `app/assets/categories.json`
- `hashtags`: hashtag ids separated by `;`
- `orientation`: `portrait` / `landscape`
- Only photos taken by team members. No internet photos. Prefer one person, portrait, full body.

Full guide: `prompts/bomin-data-guide.md`
