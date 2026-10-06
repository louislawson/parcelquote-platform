# syntax=docker/dockerfile:1

# ---- base --------------------------------------------------------------------
# Everything the builder and the runtime agree on: the pinned interpreter, the
# interpreter environment, the working directory and the unprivileged account.
# The digest is declared once here, so bumping it cannot leave the two stages
# building on different bases.
#
# No USER in this stage. The builder needs root to install Poetry; the runtime
# stage drops privileges once its copying is done.

# This is the multi-arch index digest, not the linux/amd64 one, so it resolves on any platform
# the build runs on. Bumping it is also the remedy when the Snyk container gate fails on an OS
# package: the gate passes --fail-on=upgradable, so it only ever fails on something Debian has
# already fixed, and the official image picks those up within a day or two of the advisory.
# Reach for apt-get in this file only if that window is ever genuinely too long — it trades the
# reproducibility this pin exists for, and it has not been needed yet.

# python:3.12-slim-bookworm — Python 3.12.15, Debian 12.
FROM python@sha256:34386ef0cb081344d7ec1c103ba398e6e9f64e9ab3a1509accc92a4e24a07258 AS base

# PYTHONUNBUFFERED keeps logs flowing rather than sitting in a buffer until the
# process exits, which matters once App Insights is collecting them.
# PYTHONFAULTHANDLER turns a segfault inside a C extension — uvloop and
# pydantic-core are both compiled — into a traceback rather than silence.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1

WORKDIR /app

# A fixed UID and GID rather than whatever number happens to be free, so file
# ownership means the same thing across rebuilds and between hosts. The account
# exists before any COPY --chown refers to it.
RUN groupadd --gid 10001 appuser \
 && useradd --uid 10001 --gid 10001 --create-home appuser

# ---- builder -----------------------------------------------------------------
# Poetry resolves and installs dependencies here. None of this stage reaches the
# final image: Poetry is build tooling, and every package it drags in would be
# runtime attack surface a scanner has to reason about.

FROM base AS builder

# Pinned deliberately. An unpinned Poetry means a release upstream can change how
# the lock file resolves, which is the sort of drift that shows up as a failed
# deploy rather than a failed build.
ENV POETRY_VERSION=2.4.3 \
    POETRY_NO_INTERACTION=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN pip install --no-cache-dir "poetry==${POETRY_VERSION}"

# Manifests before source. The source changes every commit; poetry.lock rarely
# does, so the dependency layer below survives most builds.
#
# README.md is here because pyproject.toml declares `readme = "README.md"`, and
# Poetry reads it when it installs the root package. Omit it and the build fails
# on a missing file that does not obviously point back at the readme.
#
# poetry.toml sets in-project virtualenvs, so the venv lands at /app/.venv — a
# fixed path the runtime stage can copy from.
COPY pyproject.toml poetry.lock poetry.toml README.md ./

# --only main drops pytest, ruff and httpx. --no-root installs the dependencies
# without the package itself, so this layer is keyed on the lock file alone and
# is not invalidated by application changes.
#
# No wheel-building stage: every dependency resolves to a prebuilt manylinux
# wheel, which is why this succeeds on a slim base that has no compiler.
RUN --mount=type=cache,target=/root/.cache/pypoetry \
    poetry install --only main --no-root

COPY src ./src

RUN --mount=type=cache,target=/root/.cache/pypoetry \
    poetry install --only main

# ---- test --------------------------------------------------------------------
# Not built by default — `docker build --target test .` runs it, and a red test
# or a lint failure fails the build. This is the CI parity target; for a local
# edit loop use `poetry run uvicorn --reload`, which needs no image at all.

FROM builder AS test

RUN --mount=type=cache,target=/root/.cache/pypoetry \
    poetry install --with dev

COPY tests ./tests

# Lint at build time: it produces no report worth publishing, and a failure here
# means no test image is produced at all.
RUN poetry run ruff check .

RUN mkdir -p /app/reports

# Tests run at container run time, not in a layer, so the reports survive a
# failure. A RUN that fails exports nothing, which is the one case the reports
# matter most.
CMD ["poetry", "run", "pytest", "-q", \
     "--junitxml=/app/reports/junit.xml", \
     "--cov=parcelquote", \
     "--cov-report=xml:/app/reports/coverage.xml", \
     "--cov-report=term", \
     "--cov-fail-under=85"]

# ---- runtime -----------------------------------------------------------------

FROM base AS runtime

ARG GIT_SHA=dev

# ARG does not survive into the running container. Without promoting it to ENV,
# /version reports "dev" in production and the canary check becomes meaningless.
#
# PATH puts the virtualenv first so `uvicorn` resolves without an absolute path.
ENV GIT_SHA=${GIT_SHA} \
    PATH="/app/.venv/bin:${PATH}"

# A virtualenv hardcodes its own absolute path in pyvenv.cfg and its scripts, so
# it has to land at exactly the /app/.venv it was built at.
COPY --from=builder --chown=appuser:appuser /app/.venv /app/.venv
COPY --from=builder --chown=appuser:appuser /app/src /app/src

# pip's vendored libraries were the only Python CVEs in this image, and nothing
# installs packages at run time. An image without pip is one nothing can add to.
RUN rm -rf /usr/local/lib/python3.*/site-packages/pip* \
           /app/.venv/lib/python3.*/site-packages/pip*

USER appuser

# Documentation only. Publishing is decided at run time, by the runtime.
EXPOSE 8000

# Exec form, so uvicorn is PID 1 and receives SIGTERM directly rather than through
# a shell that would swallow it and force a kill after the grace period.
#
# --host 0.0.0.0 because uvicorn defaults to 127.0.0.1, which binds inside the
# container only and makes a correct port mapping look broken.
CMD ["uvicorn", "parcelquote.main:app", "--host", "0.0.0.0", "--port", "8000"]
