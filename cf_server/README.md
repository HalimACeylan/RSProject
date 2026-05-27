# CF Recommendation Service

A FastAPI wrapper around `datasets_to_use/test_ml_recommendations.py`. The Flutter app calls this at `http://localhost:8000` to get collaborative-filtering recommendations; the Dart KB recommender handles everything else and is the fallback if this service is unreachable.

## Run

```bash
cd cf_server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8000 --reload
```

First request triggers a one-time data load (~5–10 s) — `synthetic_interactions.csv` and `RAW_recipes_filtered.csv` from `../datasets_to_use/`.

## Endpoints

### `GET /health`
Returns recipe count, synthetic user count, and the list of available `profile_tag` values.

### `POST /recommend`
Body:

```json
{
  "profile_tag": "healthy_eater",        // optional, cold-start fallback
  "liked_recipe_ids": [31490, 44061],    // preferred — builds a TF-IDF taste vector
  "exclude_recipe_ids": [5289],          // recipes to skip
  "top_n": 5
}
```

Returns ranked `[ { recipe_id, cf_score, serendipity, name } ]`. `cf_score + serendipity` is the ranking key.

## How the Flutter app reaches this

- **Desktop / iOS simulator** → `http://localhost:8000`
- **Android emulator** → `http://10.0.2.2:8000`

If the service is not running, the app silently falls back to KB-only recommendations — no error shown to the user beyond a small "CF offline" hint.
