---
title: ATS Resume Analyzer API
emoji: 📄
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
---

# ATS Resume Analyzer

AI-powered résumé scorer: parses a résumé, extracts structured data with an LLM,
and scores it across formatting, keywords, content, skill-validation, and
ATS-compatibility — with optional job-description matching using a finetuned
sentence-transformer.

- **Backend** — FastAPI + spaCy + a finetuned `all-mpnet-base-v2`, served via Docker
  (this Space). Listens on port **7860**.
- **Frontend** — Streamlit app (deployed separately on Streamlit Community Cloud).
- **Auth & storage** — Supabase (JWT auth + analysis history).

> The YAML header above configures the Hugging Face Space. See **[DEPLOY.md](DEPLOY.md)**
> for full deployment steps (model upload, secrets, CORS, Supabase redirect URLs).

## Local development

```bash
# Backend  (http://localhost:8000)
uv run --python .venv python -m backend.main

# Frontend (http://localhost:8501)
uv run --python .venv streamlit run frontend/streamlit_app.py
```

Backend env vars live in `backend/.env`; frontend secrets in `.streamlit/secrets.toml`
(see `.streamlit/secrets.toml.example`).
