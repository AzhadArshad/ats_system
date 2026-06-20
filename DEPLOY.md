# Deployment Guide — free stack

**Backend** → Hugging Face Spaces (Docker, free CPU tier — ~16 GB RAM, fits the model)
**Frontend** → Streamlit Community Cloud (free)
**Auth/DB** → your existing Supabase project

Total cost: **$0**. The only caveat: a free Space sleeps after ~48 h idle and cold-starts
(~30–60 s to reload the model) on the next request.

---

## Part 1 — Push the finetuned model to the HF Hub (one time)

The 438 MB model is gitignored and not in the repo. Host it on the Hub (free, public is
fine — it's not sensitive); the backend downloads it at startup.

```bash
pip install -U "huggingface_hub[cli]"
huggingface-cli login                      # paste a token from huggingface.co/settings/tokens

# create + upload (replace YOUR_USERNAME)
huggingface-cli upload YOUR_USERNAME/ats-mpnet ml_models/finetuned-bert . --repo-type=model
```

You now have a model at `YOUR_USERNAME/ats-mpnet`. The backend's
`SENTENCE_TRANSFORMER_MODEL` env var (already wired in `backend/core/config.py`) will point
at it — no code change needed.

---

## Part 2 — Deploy the backend to a Hugging Face Space

1. **Create the Space**: huggingface.co → *New Space* → **SDK: Docker**, **blank/empty**,
   hardware **CPU basic (free)**.
2. **Push the code** to the Space's git repo (it needs `Dockerfile`, `requirements-backend.txt`,
   `backend/`, and a `README.md` with the Docker frontmatter — all already in this repo):
   ```bash
   git remote add space https://huggingface.co/spaces/YOUR_USERNAME/ats-backend
   git push space main
   ```
   *(Alternatively, link this GitHub repo to the Space in the Space settings.)*
3. **Set secrets** in *Space → Settings → Variables and secrets* (these become env vars):

   | Name | Value |
   |------|-------|
   | `SENTENCE_TRANSFORMER_MODEL` | `YOUR_USERNAME/ats-mpnet` |
   | `GROQ_API_KEY` | your Groq key |
   | `SUPABASE_URL` | `https://xgpxvzlxpyxhltbriejf.supabase.co` |
   | `SUPABASE_KEY` | your **service_role** key (backend only) |
   | `SUPABASE_JWT_SECRET` | from Supabase → *Settings → API → JWT Secret* (needed for HS256 tokens) |
   | `ALLOWED_ORIGINS` | `https://YOUR-APP.streamlit.app` (fill in after Part 3) |

4. The Space builds and starts on port 7860. Confirm it's live:
   ```
   https://YOUR_USERNAME-ats-backend.hf.space/api/v1/health
   ```
   Expect `{"status":"healthy","nlp_loaded":true,"embedder_loaded":true}`.

> **Auth note:** `auth.py` verifies Supabase JWTs either via JWKS (asymmetric RS256/ES256,
> using `SUPABASE_URL`) or HS256 (using `SUPABASE_JWT_SECRET`). New Supabase projects use
> asymmetric keys (JWKS) — the URL alone is enough. If yours issues HS256, the real
> `SUPABASE_JWT_SECRET` is required (the current `backend/.env` value is a placeholder).

---

## Part 3 — Deploy the frontend to Streamlit Community Cloud

1. share.streamlit.io → *New app* → pick this repo.
2. **Main file path**: `frontend/streamlit_app.py`
   → Streamlit Cloud uses `frontend/requirements.txt` (the slim file), not the heavy root one.
3. **Advanced settings → Python version**: `3.11`.
4. **Advanced settings → Secrets**: paste (same shape as `.streamlit/secrets.toml`, with the
   deployed backend URL):
   ```toml
   [supabase]
   SUPABASE_URL = "https://xgpxvzlxpyxhltbriejf.supabase.co"
   SUPABASE_ANON_KEY = "<your-anon-key>"

   [google_oauth]
   redirect_uri = "https://YOUR-APP.streamlit.app"

   [backend]
   url = "https://YOUR_USERNAME-ats-backend.hf.space"
   ```
5. Deploy. Note the final URL `https://YOUR-APP.streamlit.app`.

---

## Part 4 — Wire the two together

1. **CORS**: set the Space's `ALLOWED_ORIGINS` secret to `https://YOUR-APP.streamlit.app`
   and restart the Space.
2. **Supabase redirect URLs**: *Auth → URL Configuration → Redirect URLs* → add
   `https://YOUR-APP.streamlit.app`.
3. **Google OAuth** (if enabled): in Google Cloud Console add the same URL, and ensure the
   Supabase callback `https://xgpxvzlxpyxhltbriejf.supabase.co/auth/v1/callback` is an
   authorized redirect URI.

---

## Verify end-to-end

1. Open `https://YOUR-APP.streamlit.app`, sign up / sign in.
2. Upload a résumé on the Scorer page → you should get a score + feedback (first request
   after a cold start is slow while the model downloads/loads).
3. PDF export works because the Docker image installs WeasyPrint's system libs.

## Notes / gotchas

- **Cold starts**: free Spaces sleep; first hit reloads the model. To avoid the runtime
  download you can instead bake the model into the image (uncomment a build-time
  `SentenceTransformer(...)` pull in the Dockerfile) — costs image size, saves cold-start time.
- **`requirements.txt` resolution on Streamlit Cloud**: if it ever picks the heavy root file
  and the build fails on WeasyPrint, confirm the main file path is `frontend/streamlit_app.py`
  so `frontend/requirements.txt` is used.
- **Model escape hatch**: if `SENTENCE_TRANSFORMER_MODEL` is unset/invalid, the backend falls
  back to the lightweight `all-MiniLM-L6-v2` (lower quality, but boots anywhere).
