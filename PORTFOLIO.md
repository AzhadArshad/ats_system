# ATS Resume Analyzer

> An AI résumé scorer that reads a résumé like a recruiter would — LLM extraction, a finetuned transformer for semantic judgment, and a deterministic scoring layer behind a single file upload.

## The Origin

This started in a classroom. I was working through **Apna College's** course, and this became one of the major hands-on projects in the curriculum. But "build a résumé checker" could have meant counting keywords and calling it done. I wanted the score to actually *mean* something — to reflect whether a résumé backs up what it claims, the way a recruiter reading it decides in fifteen seconds.

That framing is what made it interesting: an LLM doing structured extraction, a finetuned sentence-transformer doing semantic judgment, and a deterministic scoring engine tying them together — all hidden behind one upload button.

## The Approach

Every upload runs through a five-stage pipeline. The raw file is validated and text-extracted — pdfplumber with a PyPDF2 fallback for PDFs, python-docx for Word, libmagic to sniff the *real* MIME type instead of trusting the extension. The text goes to a Groq-hosted **LLaMA 3.3 70B at temperature 0**, which returns the résumé as structured JSON: skills, experience with durations, projects with tech stacks, action verbs. From there a scoring engine computes five weighted components, and if a job description is supplied, a finetuned transformer measures semantic fit.

FastAPI owns all of it. The models load **once at startup** through the lifespan context — spaCy and the transformer are expensive to initialize, so they live in app state for the life of the process, never per-request. Streamlit drives the UI; Supabase handles auth and per-user history.

## The Hard Part: Making the Score Honest

The architecture wasn't the hard part. The hard part was deciding what a "good" résumé actually *is*, in numbers. Anyone can count keywords — and the problem with keyword counting is that it rewards lying. Paste a skills section full of buzzwords and you win.

So the core of the scorer is **skill validation**: a claimed skill only counts if there's evidence for it elsewhere in the résumé. For each skill I first try a cheap substring match against the projects and experience text. If that misses, I fall back to semantic similarity — embed the skill and the section, take the cosine, accept it only if it clears a threshold. "Kubernetes" in your skills list but never mentioned in a single project? Unvalidated. That one decision is what separates this from a keyword grep.

```python
# backend/services/ats_scorer.py — a skill only counts if the résumé backs it up
def _skill_matches(skill, text, embedder, threshold):
    # fast path: is the skill mentioned verbatim?
    if skill.lower() in text.lower():
        return True, 1.0
    # slow path: is it semantically present in projects / experience?
    sim = _calculate_semantic_similarity(skill, text, embedder)
    return sim >= threshold, sim
```

The semantic half runs on an **all-mpnet-base-v2** model I finetuned on résumé/JD pairs — Spearman 0.86 on the validation set, ~45% MAE improvement over the base model. A small model trained on the exact thing you're measuring beats a general-purpose giant asked to "rate this résumé": it's faster, cheaper, and far more consistent.

> A keyword counter tells you what words are on the page. Semantic skill-validation tells you whether the page is telling the truth — and the score is only as honest as the evidence behind it.

## What Broke (And What I Learned)

LLMs lie about their output format. Groq is fast, but "return JSON" is a request, not a guarantee — sometimes it wraps the object in markdown fences, sometimes it prepends a sentence of preamble. The parser strips code fences first, and if the result still won't parse, it retries once with a stricter prompt before giving up. Treating the model as an *unreliable narrator* and building a recovery path around it was the difference between a demo and something that survives real uploads.

```python
# backend/services/groq_parser.py — surviving an LLM that won't return clean JSON
result = _try_parse_json(raw_response)        # strips ``` fences, then json.loads
if result is not None:
    return _validate_resume_result(result)

# the LLM didn't return clean JSON — retry once, stricter
strict = "Return ONLY the raw JSON object, no markdown, no fences.\n\n" + prompt
result = _try_parse_json(_call_groq(client, SYSTEM_PROMPT, strict))
if result is not None:
    return _validate_resume_result(result)
raise ValueError("Groq returned unparseable JSON after retry")
```

Deployment was its own lesson. Half my dependencies aren't Python — **libmagic** and **WeasyPrint's** cairo/pango stack are system libraries pip can't touch, so the backend had to be Dockerized to be reproducible across machines. And the 438 MB finetuned model is too big for git, so it's hosted on the Hugging Face Hub and pulled at runtime via an env var, with a fallback to a lighter model if it's ever missing so the service always boots. Backend runs on HF Spaces (Docker), frontend on Streamlit Cloud — total hosting cost: **zero**.

```python
# backend/core/config.py — finetuned model from the Hub, with a fallback that always boots
SENTENCE_TRANSFORMER_MODEL = os.getenv(
    "SENTENCE_TRANSFORMER_MODEL",
    str(FINETUNED_DIR) if FINETUNED_DIR.exists() else "all-MiniLM-L6-v2",
)
```

## What It Does

Upload a PDF or DOCX résumé, optionally paste a job description, and get back:

- A **0–100 ATS score** with a five-component breakdown — formatting, keywords, content, skill validation, ATS compatibility
- **Skill validation** — which claimed skills are actually backed by evidence, and which aren't
- **Job-description matching** — match %, matched and missing keywords, skill gaps
- **Prioritized feedback** across ten issue categories, each with severity, ATS impact, and a concrete fix
- A styled **PDF report**, plus saved history per account (Supabase auth)

## What I'd Build Differently

Three things. The Groq extraction would move to **structured / function-calling output** instead of prompt-and-pray JSON parsing — the retry loop works, but the model should be constrained at the API level, not patched after the fact. The **grammar component is currently a stub**: it has consumers wired up but no engine, and I'd back it with either a lightweight checker or a dedicated LLM pass. And the skill-validation **threshold was tuned for the original lightweight model** — swapping in the finetuned mpnet shifted the similarity distribution, so it deserves a proper recalibration against labeled data rather than a hand-picked constant.

---

**Built with:** FastAPI · Streamlit · Groq (LLaMA 3.3 70B) · sentence-transformers (mpnet) · spaCy · rapidfuzz · Supabase · Docker · HF Spaces · WeasyPrint · pdfplumber
