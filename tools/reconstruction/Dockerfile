# CPU default. Set BASE_IMAGE to the pinned CUDA image and GPU_RUNTIME=CUDA for NVIDIA.
# These LibTorch archives target x86_64; Apple Silicon Docker must use linux/amd64.
ARG BASE_IMAGE=ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401
FROM ${BASE_IMAGE}
ARG TARGETARCH
ARG GPU_RUNTIME=CPU
ARG BUILD_JOBS=2
ARG CUDA_ARCHITECTURES=75;80;86;89
ENV DEBIAN_FRONTEND=noninteractive
RUN test "${TARGETARCH}" = amd64 && apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git build-essential cmake ninja-build unzip python3 python3-pip \
    libboost-all-dev libeigen3-dev libceres-dev libflann-dev libfreeimage-dev \
    libgoogle-glog-dev libgtest-dev libglew-dev libmetis-dev libsqlite3-dev liblz4-dev \
    libcgal-dev libopencv-dev libgmp-dev libmpfr-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/kantura
COPY pins.json requirements.txt engines-build.sh ./
RUN python3 -m pip install --no-cache-dir -r requirements.txt
RUN GPU_RUNTIME="${GPU_RUNTIME}" BUILD_JOBS="${BUILD_JOBS}" CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" bash ./engines-build.sh
COPY patches ./patches
COPY openmvs-patch.sh ./
RUN BUILD_JOBS="${BUILD_JOBS}" bash ./openmvs-patch.sh
COPY contract.py worker.py service.py ./
COPY README.md API.md THIRD-PARTY.md ./
RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin kantura && \
    mkdir /data && chown kantura:kantura /data
ENV PATH=/usr/local/bin:/usr/local/bin/OpenMVS:${PATH} \
    LD_LIBRARY_PATH=/opt/kantura/libtorch/lib:/usr/local/lib \
    HOST=0.0.0.0 PORT=4180 DATA_DIR=/data WORKER_DEVICE=cpu \
    WORKER_THREADS=2 IMAGE_MAX_SIDE=1600 SPLAT_ITERATIONS=1000 \
    PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 QT_QPA_PLATFORM=offscreen
USER 10001:10001
EXPOSE 4180
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:4180/health', timeout=3).read()"
CMD ["python3", "/opt/kantura/service.py"]
