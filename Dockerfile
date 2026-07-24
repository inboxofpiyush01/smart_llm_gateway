FROM python:3.11-slim

ARG APP_PORT=8501
ENV PORT=${APP_PORT} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN useradd --create-home --uid 10001 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE ${APP_PORT}
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import os,socket; p=int(os.environ.get('PORT','8501')); s=socket.socket(); s.settimeout(2); s.connect(('127.0.0.1',p))" || exit 1

CMD ["sh","-c","exec streamlit run \"app.py\" --server.port=${PORT:-8501} --server.address=0.0.0.0 --server.headless=true --server.enableCORS=false --server.enableXsrfProtection=false"]
