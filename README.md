---
title: ATS Resume Analyzer API
emoji: 📄
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
---

# 📄 ATS Resume Analyzer

An AI-powered Applicant Tracking System (ATS) résumé scorer. Upload a résumé (and
optionally a job description) and get back a **0–100 ATS score**, a component-by-component
breakdown, evidence-backed skill validation, prioritized fix-it feedback, job-description
matching, and a downloadable PDF report.

Unlike keyword-counting "ATS checkers," this system **reads the résumé like a recruiter
would**: it extracts structured data with an LLM, validates that claimed skills are actually
backed by projects/experience, and measures semantic fit against a job description using a
**finetuned sentence-transformer** trained on résumé/JD pairs.

> **Live:** Backend on Hugging Face Spaces · Frontend on Streamlit Community Cloud.
> See **[DEPLOY.md](DEPLOY.md)** for the full (free) deployment guide.

---

## ✨ Features

- **Structured résumé parsing** via LLM — name, contact, summary, skills, experience (with
  durations), education, certifications, projects (with tech stacks), action verbs, keywords.
- **Five-component ATS score** (0–100) with a transparent breakdown — no black box.
- **Skill validation** — every listed skill is checked for *evidence* in projects/experience
  using semantic similarity, so "Python" only counts if you actually used it somewhere.
- **Job-description matching** — keyword overlap + semantic similarity from a finetuned BERT,
  surfacing matched keywords, missing keywords, and skill gaps.
- **Actionable feedback** — issues are detected across 10 categories, each with severity,
  ATS impact, how-to-fix, and an example improvement.
- **Location-privacy detection** — flags street addresses / ZIP codes that don't belong on a résumé.
- **PDF reports** — a combined, styled report rendered server-side with WeasyPrint.
- **Accounts & history** — Supabase auth (email/password + Google OAuth) with per-user
  analysis history.

---

## 🏗️ Architecture

A three-tier system: a Streamlit UI, a FastAPI service that owns all the ML/NLP, and Supabase
for auth + storage.

```
┌──────────────────────┐        HTTPS / JWT        ┌───────────────────────────────┐
│   Streamlit frontend │ ────────────────────────▶ │      FastAPI backend          │
│  (Streamlit Cloud)   │   POST /api/v1/analyze    │   (HF Spaces, Docker:7860)    │
│                      │ ◀──────────────────────── │                               │
│  • auth UI           │      AnalysisResponse     │  spaCy ┄ SentenceTransformer  │
│  • upload + results  │                           │  Groq LLM ┄ WeasyPrint        │
└──────────┬───────────┘                           └───────────────┬───────────────┘
           │                                                        │
           │  Supabase JS (auth, history)          Supabase REST (service role)
           ▼                                                        ▼
        ┌──────────────────────────── Supabase ───────────────────────────────┐
        │   Auth (JWT)        ·        Postgres: `analyses` (per-user history)  │
        └──────────────────────────────────────────────────────────────────────┘
```

### The analysis pipeline

A single upload flows through five stages (`backend/services/resume_analyzer.py` is the
orchestrator):

```
1. PARSE FILE      pdfplumber → PyPDF2 fallback (PDF) / python-docx (DOCX)   → raw text
2. LLM EXTRACT     Groq (llama-3.3-70b-versatile, temp=0) → structured JSON  → parsed résumé
3. SCORE           5 weighted components + bonuses/penalties                 → 0–100 ATS score
4. JD MATCH        keyword overlap (rapidfuzz) + semantic sim (finetuned BERT)→ match %, gaps
5. FEEDBACK        10 issue detectors + prioritized recommendations          → fix-it report
```

---

## 🎯 How the ATS score works

The score is the sum of **five components** (max 100), each measuring a distinct dimension.
The weights live in `backend/core/config.py` (`SCORE_WEIGHTS`):

| Component | Max | What it measures |
|-----------|-----|------------------|
| **Formatting** | 20 | Presence of core sections (experience, education, skills, summary, projects), bullet-point usage, section completeness |
| **Keywords** | 25 | Keyword & skill richness, plus fuzzy match against the job description's keywords |
| **Content** | 25 | Strong action verbs, quantified achievements (metrics/numbers), grammar quality |
| **Skill validation** | 15 | % of listed skills that are *backed by evidence* in projects/experience |
| **ATS compatibility** | 15 | Penalties for privacy risks (addresses/ZIP), problematic special characters, too-short sections |

**Skill validation** is the differentiator: for each skill, the backend first does a fast
substring check, then falls back to **semantic similarity** (`sentence-transformers`, cosine
≥ threshold) against the text of your projects and experience. A skill with no evidence is
reported as *unvalidated* — which is exactly what a real recruiter would discount.

---

## 🧠 The finetuned model

JD matching and skill validation use a **finetuned `all-mpnet-base-v2`** sentence-transformer
(`ml_models/finetuned-bert/`), trained on résumé/JD pairs with `CosineSimilarityLoss`.

| Metric (validation set) | Value |
|-------------------------|-------|
| Spearman (cosine) | **0.86** |
| Pearson (cosine) | **0.89** |
| MAE improvement over base | **~45%** |

In production the model is hosted on the HF Hub and pulled at runtime via the
`SENTENCE_TRANSFORMER_MODEL` env var. If that's unset/unavailable, the backend transparently
falls back to the lighter `all-MiniLM-L6-v2` so it always boots.

---

## 🧩 Tech stack

| Layer | Tech |
|-------|------|
| **Frontend** | Streamlit |
| **API** | FastAPI, Uvicorn, Pydantic |
| **NLP / ML** | spaCy (`en_core_web_md`), sentence-transformers (finetuned mpnet), rapidfuzz |
| **LLM** | Groq — `llama-3.3-70b-versatile` (structured extraction) |
| **File parsing** | pdfplumber, PyPDF2, python-docx, python-magic |
| **Reports** | Jinja2 + WeasyPrint (HTML → PDF) |
| **Auth & DB** | Supabase (JWT verified via JWKS/HS256; Postgres via REST) |
| **Deploy** | Docker → HF Spaces (backend) · Streamlit Cloud (frontend) |

---

## 📁 Project structure

```
ats_system/
├── backend/
│   ├── main.py                 # FastAPI app, model loading on startup, root + CORS
│   ├── api/
│   │   ├── routes.py           # /api/v1 endpoints
│   │   └── auth.py             # Supabase JWT verification (JWKS + HS256)
│   ├── core/config.py          # env, model names, score weights, CORS
│   ├── services/
│   │   ├── resume_analyzer.py  # pipeline orchestrator
│   │   ├── resume_parser.py    # file validation + text extraction
│   │   ├── groq_parser.py      # LLM structured extraction (résumé + JD)
│   │   ├── ats_scorer.py       # 5-component scoring + skill validation + location
│   │   ├── jd_matcher.py       # résumé ↔ JD keyword + semantic matching
│   │   ├── feedback_engine.py  # 10 issue detectors
│   │   ├── recommendation_engine.py
│   │   ├── report_generator.py # Jinja2 HTML reports
│   │   └── pdf_export.py       # WeasyPrint PDF
│   ├── models/schemas.py       # Pydantic request/response models
│   ├── database/supabase_db.py # history save/fetch/delete (REST)
│   └── templates/              # Jinja2 report templates
├── frontend/
│   ├── streamlit_app.py        # entry, routing, auth state
│   ├── views/                  # landing, scorer, history, resources
│   ├── components/             # score display, feedback, JD comparison, …
│   └── services/               # api_client, supabase_client
├── ml_models/finetuned-bert/   # finetuned mpnet (gitignored; hosted on HF Hub)
├── Dockerfile                  # backend image (HF Spaces / Render / Cloud Run)
├── requirements.txt            # combined deps (local dev)
├── requirements-backend.txt    # backend-only deps (Docker image)
├── frontend/requirements.txt   # slim frontend deps (Streamlit Cloud)
└── DEPLOY.md                   # deployment guide
```

---

## 🔌 API endpoints

All under `/api/v1`, JWT-protected unless noted.

| Method | Path | Description |
|--------|------|-------------|
| `GET`  | `/` | Service info (public; also HF Spaces readiness probe) |
| `GET`  | `/api/v1/health` | Models-loaded health check (public) |
| `POST` | `/api/v1/analyze-resume` | Upload résumé (+ optional JD) → full analysis |
| `GET`  | `/api/v1/history` | Signed-in user's past analyses |
| `DELETE` | `/api/v1/history/{id}` | Delete one analysis |
| `POST` | `/api/v1/generate-pdf` | Render an analysis to a combined PDF |
| `GET`  | `/api/v1/history/{id}/pdf` | PDF for a stored analysis |

Interactive docs at `/docs` (Swagger) and `/redoc`.

---

## 🚀 Local development

**Prerequisites:** Python 3.11, a virtualenv at `.venv`, and system libs for parsing/PDF:

```bash
# macOS
brew install libmagic cairo pango gdk-pixbuf libffi
```

**Install & run:**

```bash
# install deps
pip install -r requirements.txt
python -m spacy download en_core_web_md

# backend  → http://localhost:8000
uv run --python .venv python -m backend.main

# frontend → http://localhost:8501   (separate terminal)
uv run --python .venv streamlit run frontend/streamlit_app.py
```

### Configuration

| Where | File | Keys |
|-------|------|------|
| Backend | `backend/.env` | `GROQ_API_KEY`, `SUPABASE_URL`, `SUPABASE_KEY`, `SUPABASE_JWT_SECRET`, `SENTENCE_TRANSFORMER_MODEL`, `ALLOWED_ORIGINS` |
| Frontend | `.streamlit/secrets.toml` | `[supabase]`, `[google_oauth]`, `[backend]` (see `.streamlit/secrets.toml.example`) |

---

## ☁️ Deployment

Backend → **Hugging Face Spaces (Docker)**, frontend → **Streamlit Community Cloud**, both on
free tiers. The finetuned model is pushed to the HF Hub and pulled at runtime. Step-by-step
instructions (model upload, secrets, CORS, Supabase redirect URLs) are in **[DEPLOY.md](DEPLOY.md)**.

---

## 📝 Notes & roadmap

- **Grammar scoring** is currently a stub (reports "unavailable") — it has consumers but no
  engine yet. Candidate approaches: `language_tool_python` or a Groq grammar pass.
- The skill-validation similarity threshold may warrant recalibration for the finetuned model.
