# Multi-architecture official Python index, resolved 2026-10-12.
FROM python:3.11.14-slim-bookworm@sha256:65a93d69fa75478d554f4ad27c85c1e69fa184956261b4301ebaf6dbb0a3543d
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2
WORKDIR /opt/panorama
COPY requirements.txt ./
RUN pip install --no-cache-dir --only-binary=:all: -r requirements.txt
COPY stitch.py synthetic.py test_stitch.py README.md THIRD-PARTY.md ./
RUN python -m unittest -v test_stitch
RUN useradd --create-home --uid 10001 panorama
USER 10001:10001
ENTRYPOINT ["python", "/opt/panorama/stitch.py"]
