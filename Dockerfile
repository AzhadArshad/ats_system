# Backend (FastAPI) image — built for Hugging Face Spaces (Docker SDK).
# Also runs as-is on Render/Cloud Run/Railway. Listens on port 7860 (HF default).
FROM python:3.11-slim

# System libraries that pip cannot provide:
#   libmagic1            -> python-magic (file type sniffing)
#   libcairo2 / pango /  -> WeasyPrint (PDF export)
#   gdk-pixbuf / libffi
#   shared-mime-info     -> libmagic MIME database
RUN apt-get update && apt-get install -y --no-install-recommends \
        libmagic1 \
        libcairo2 \
        libpango-1.0-0 \
        libpangoft2-1.0-0 \
        libgdk-pixbuf-2.0-0 \
        libffi-dev \
        shared-mime-info \
    && rm -rf /var/lib/apt/lists/*

# HF Spaces runs containers as uid 1000 — create a matching user with a writable
# home so the HF model cache (HF_HOME) and pip user installs work.
RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH \
    HF_HOME=/home/user/.cache/huggingface \
    PYTHONUNBUFFERED=1

WORKDIR /home/user/app

# Install Python deps first (layer-cached across code changes)
COPY --chown=user requirements-backend.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements-backend.txt \
    && python -m spacy download en_core_web_md

# App code (the embedding model is NOT copied — it is pulled from the HF Hub at
# runtime via the SENTENCE_TRANSFORMER_MODEL env var; see DEPLOY.md)
COPY --chown=user backend ./backend

EXPOSE 7860
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "7860"]
