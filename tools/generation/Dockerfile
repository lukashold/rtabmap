# Build context: tools/generation. Model downloads happen only in this build.
ARG BASE_IMAGE=ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401
FROM ${BASE_IMAGE}
ARG TARGETARCH
ARG BUILD_JOBS=2
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
RUN test "${TARGETARCH}" = amd64 && apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git build-essential cmake ninja-build python3 python3-pip python3-dev python3-venv \
    libgomp1 && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/kantura-generation
COPY requirements.txt pins.json download_models.py patch_vendor.py install-runtime.sh ./
COPY input_contract.py generate.py ./
COPY test ./test
RUN BUILD_JOBS="${BUILD_JOBS}" bash ./install-runtime.sh /opt/kantura-generation
COPY README.md THIRD-PARTY.md ./
COPY licenses ./licenses
ENV PYTHONPATH=/opt/triposr KANTURA_MODEL_DIR=/opt/kantura-models \
    KANTURA_DINO_CONFIG=/opt/kantura-models/dino-config.json \
    HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1 \
    TOKENIZERS_PARALLELISM=false OMP_NUM_THREADS=2
RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin kantura
USER 10001:10001
ENTRYPOINT ["/opt/kantura-generation-env/bin/python", "/opt/kantura-generation/generate.py"]
