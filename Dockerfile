# The demo app as one container, on Lambda behind a streaming Function URL (challenge/infra/app.tf; DECISIONS.md,
# Deploy). The Lambda Web Adapter extension runs uvicorn unchanged and streams its SSE responses; under plain docker run
# the extension is inert, so the same image runs anywhere. App Runner's fixed 120 s request limit is why it is not App Runner.
#   docker build --platform linux/amd64 --build-arg AGENT_GIT_SHA=$(git rev-parse HEAD) -t lantern .
#   docker run --rm -p 8080:8080 --env-file challenge/.env lantern      # then curl localhost:8080/health
# Configuration is the environment only: ANTHROPIC_API_KEY (or ANTHROPIC_API_KEY_SSM, a parameter name), PGHOST, PGPORT,
# PGDATABASE, PGSSLMODE, AGENT_PGUSER, AGENT_PGPASSWORD, REVIEWER_PGUSER, REVIEWER_PGPASSWORD. No .env, raw/, or
# credential is copied in (.dockerignore is a whitelist). The build context is the repo root because agent.py and
# evals.py find challenge/eval/ by walking up from their own files.
FROM python:3.13-slim
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0 /lambda-adapter /opt/extensions/lambda-adapter
WORKDIR /srv
COPY challenge/prototype/requirements.txt challenge/prototype/
COPY challenge/app/requirements.txt challenge/app/
RUN pip install --no-cache-dir -r challenge/app/requirements.txt
COPY challenge/prototype challenge/prototype
COPY challenge/app challenge/app
COPY challenge/eval/questions.yaml challenge/eval/experiments.jsonl challenge/eval/truth.json challenge/eval/
ARG AGENT_GIT_SHA=""
ENV AGENT_GIT_SHA=$AGENT_GIT_SHA RAW_DIR=/tmp/raw PYTHONUNBUFFERED=1 \
    AWS_LWA_INVOKE_MODE=response_stream AWS_LWA_READINESS_CHECK_PATH=/health
EXPOSE 8080
CMD ["python", "-m", "uvicorn", "main:app", "--app-dir", "challenge/app", "--host", "0.0.0.0", "--port", "8080"]
