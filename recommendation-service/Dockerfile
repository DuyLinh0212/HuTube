FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /service

COPY pyproject.toml ./
COPY app ./app
COPY training ./training
COPY configs ./configs
RUN python -m pip install --no-cache-dir .

RUN addgroup --system recommender \
    && adduser --system --ingroup recommender recommender \
    && mkdir -p /service/data/artifacts \
    && chown -R recommender:recommender /service

USER recommender
EXPOSE 8000

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
