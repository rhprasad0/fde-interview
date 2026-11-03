# The demo app as one container for App Runner (DECISIONS.md, Deploy).
#   docker build --build-arg AGENT_GIT_SHA=$(git rev-parse HEAD) -t lantern .
#   docker run --rm -p 8080:8080 --env-file challenge/.env lantern      # then curl localhost:8080/health
# Configuration is the environment only: ANTHROPIC_API_KEY, PGHOST, PGPORT, PGDATABASE, PGSSLMODE, AGENT_PGUSER,
# AGENT_PGPASSWORD. No .env, raw/, or credential is copied in (.dockerignore is a whitelist). The build context is the
# repo root because agent.py and evals.py find challenge/eval/ by walking up from their own files.
FROM python:3.13-slim
WORKDIR /srv
COPY challenge/prototype/requirements.txt challenge/prototype/
COPY challenge/app/requirements.txt challenge/app/
RUN pip install --no-cache-dir -r challenge/app/requirements.txt
COPY challenge/prototype challenge/prototype
COPY challenge/app challenge/app
COPY challenge/eval/questions.yaml challenge/eval/experiments.jsonl challenge/eval/truth.json challenge/eval/
ARG AGENT_GIT_SHA=""
ENV AGENT_GIT_SHA=$AGENT_GIT_SHA RAW_DIR=/tmp/raw PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["python", "-m", "uvicorn", "main:app", "--app-dir", "challenge/app", "--host", "0.0.0.0", "--port", "8080"]
