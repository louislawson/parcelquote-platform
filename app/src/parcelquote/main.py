"""FastAPI application for the parcelquote service.

Wraps the pure pricing rules in `pricing.py` with an HTTP interface. Everything
framework-shaped lives here — request and response models, routes, error mapping — so the
pricing rules stay free of FastAPI and testable without a web server.

Money and weights cross the wire as JSON **strings**, not numbers. Pydantic serialises
`Decimal` that way, and it is the behaviour we want: a JSON number becomes a float in most
clients, which is precisely what `pricing.py` uses `Decimal` to avoid. It also preserves
"9.90", where the JSON number 9.9 would lose the trailing zero a price display needs.
"""

import os
import secrets
from decimal import Decimal
from typing import Annotated, Final

from azure.monitor.opentelemetry import configure_azure_monitor
from fastapi import FastAPI, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field

from parcelquote.pricing import Zone
from parcelquote.pricing import quote as price_parcel


def _configure_telemetry() -> None:
    """Start the Azure Monitor pipeline, if this deployment has somewhere to send telemetry.

    The guard is not defensive. `configure_azure_monitor` raises without a connection string,
    so an unguarded call would break `poetry run pytest`, `poetry run uvicorn` and anything
    else importing this module on a machine with no Application Insights resource. The service
    runs locally on `QUOTE_API_KEY` alone, and should keep doing so.

    Unset is not the same as wrong, and only unset is tolerated. A connection string that is
    present but malformed is left to raise, which stops the container instead of starting it
    with telemetry silently disabled — a deployment that has been told where to send telemetry
    and then sends none is the worse failure, and a crash at least says so. It will not look
    like one: the container restarts until the revision is marked unhealthy, which reads as a
    broken image rather than a bad variable.
    """
    if not os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
        return

    configure_azure_monitor()


# Called before the FastAPI object exists, deliberately. The distro auto-instruments by
# patching the FastAPI class, so an app constructed first would not be instrumented at all —
# Microsoft's own FastAPI sample has the same order.
_configure_telemetry()

app = FastAPI(
    title="parcelquote",
    version="0.1.0",
    description="Prices parcels on chargeable weight and destination zone.",
)

# Declared once because both models carry the field. The permitted values are not restated in
# prose: the enum publishes them into the schema, and a second list of them would drift.
_ZONE_DESCRIPTION: Final = "Destination zone for the parcel"

# Every field carries an example, which is not decoration. Pydantic renders Decimal into the
# schema as a string constrained by a regex, and with no example Swagger UI invents a value
# that merely satisfies that regex: a leading plus, forty leading zeros, a hundred digits of
# nonsense. The examples below are the worked example from the README, so /docs reads true.


class Parcel(BaseModel):
    """A parcel to be priced. Dimensions in centimetres, weight in kilograms."""

    length_cm: Decimal = Field(
        gt=0,
        title="Length (cm)",
        description="Length of the parcel in centimetres",
        examples=[40],
    )
    width_cm: Decimal = Field(
        gt=0,
        title="Width (cm)",
        description="Width of the parcel in centimetres",
        examples=[30],
    )
    height_cm: Decimal = Field(
        gt=0,
        title="Height (cm)",
        description="Height of the parcel in centimetres",
        examples=[20],
    )
    weight_kg: Decimal = Field(
        gt=0,
        title="Weight (kg)",
        description="Actual weight of the parcel in kilograms",
        examples=[0.5],
    )
    zone: Zone = Field(
        title="Destination Zone", description=_ZONE_DESCRIPTION, examples=["eu"]
    )


class QuoteResponse(BaseModel):
    """A priced quote, with the weights that produced it.

    Named apart from `pricing.Quote` deliberately. That one is the domain object; this one is
    the wire format and the OpenAPI schema. Collapsing them is how framework concerns start
    leaking back into the pricing rules.
    """

    price: Decimal = Field(
        title="Price", description="Quoted price for the parcel", examples=["14.99"]
    )
    actual_weight_kg: Decimal = Field(
        title="Actual Weight (kg)",
        description="The actual weight of the parcel in kilograms",
        examples=["0.5"],
    )
    volumetric_weight_kg: Decimal = Field(
        title="Volumetric Weight (kg)",
        description="The space the parcel occupies, expressed as a weight in kilograms",
        examples=["4.8"],
    )
    chargeable_weight_kg: Decimal = Field(
        title="Chargeable Weight (kg)",
        description="The greater of the actual and volumetric weights, which sets the price",
        examples=["4.8"],
    )
    zone: Zone = Field(
        title="Destination Zone", description=_ZONE_DESCRIPTION, examples=["eu"]
    )


class ErrorResponse(BaseModel):
    """A well-formed request refused by a business rule.

    Deliberately a different shape from the 422 that field validation returns, which is a
    list of per-field errors. One status code returning two shapes would be worse.
    """

    detail: str = Field(
        title="Detail",
        description="Why the request was refused",
        examples=["chargeable weight 200 kg exceeds the maximum of 50 kg"],
    )


class Health(BaseModel):
    """The result of a probe."""

    status: str = Field(title="Status", description="Probe result")


class Version(BaseModel):
    """Build identity of the running service."""

    git_sha: str = Field(title="Git SHA", description="Commit the image was built from")


# auto_error is off deliberately. With it on, FastAPI refuses a request carrying no header
# before this function runs, so a service with no key configured would answer 401 to one
# caller and 503 to another for the same fault — and the 401 would blame the caller for the
# server's misconfiguration.
_api_key_header = APIKeyHeader(
    name="X-API-Key",
    description="Key authenticating the caller",
    auto_error=False,
    scheme_name="ApiKeyAuth",
)


def require_api_key(supplied: Annotated[str | None, Security(_api_key_header)]) -> None:
    """Refuse the request unless it carries the configured API key.

    The configured key is read per request rather than at import, for the same reason as
    `version()`: a module-level read is fixed at first import, long before any test runs.

    Raises:
        HTTPException: 503 when no key is configured, because the service then cannot serve
            its only real endpoint and the fault is the operator's; 401 when the supplied
            key is absent or wrong, which is the caller's.
    """
    configured = os.environ.get("QUOTE_API_KEY")
    if not configured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="no API key is configured, so the service cannot accept requests",
        )

    # Compared as bytes with compare_digest, not with ==. A plain comparison returns early
    # on the first wrong character, which leaks the key a character at a time to anyone
    # timing the response; and compare_digest on str raises TypeError for any non-ASCII
    # character, which a caller could send at will to turn a 401 into a 500.
    if supplied is None or not secrets.compare_digest(
        supplied.encode("utf-8"), configured.encode("utf-8")
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="a valid X-API-Key header is required",
            headers={"WWW-Authenticate": "ApiKeyAuth"},
        )


@app.post(
    "/quote",
    response_model=QuoteResponse,
    summary="Request a quote for a parcel",
    response_description="The quote for the parcel",
    responses={
        400: {
            "model": ErrorResponse,
            "description": "The parcel exceeds the maximum chargeable weight",
        },
        401: {
            "model": ErrorResponse,
            "description": "The X-API-Key header is missing or does not match",
        },
        503: {
            "model": ErrorResponse,
            "description": "The service has no API key configured",
        },
    },
    # On the decorator rather than in the signature: the handler never needs the key's
    # value, and a parameter it does not use is how an accidental query parameter gets
    # published into the schema.
    dependencies=[Security(require_api_key)],
    operation_id="quote",
)
def quote(parcel: Parcel) -> QuoteResponse:
    """Price a parcel for a destination zone.

    Returns the price along with the weights behind it, so a caller can see whether the
    actual or the volumetric weight determined the charge.

    A parcel too heavy to move through the parcel network is rejected with `400`. That is a
    well-formed request breaking a business rule, as distinct from the `422` returned for a
    request that fails field validation.
    """
    # Only the pricing call is guarded, so a bug elsewhere in this handler still surfaces as a
    # 500 rather than being reported to the caller as their mistake.
    try:
        priced = price_parcel(
            length_cm=parcel.length_cm,
            width_cm=parcel.width_cm,
            height_cm=parcel.height_cm,
            weight_kg=parcel.weight_kg,
            zone=parcel.zone,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    # Built field by field rather than converted from the dataclass. It is a few more lines,
    # but a renamed field then fails to type-check instead of at runtime on a live request.
    return QuoteResponse(
        price=priced.price,
        actual_weight_kg=priced.actual_weight_kg,
        volumetric_weight_kg=priced.volumetric_weight_kg,
        chargeable_weight_kg=priced.chargeable_weight_kg,
        zone=priced.zone,
    )


@app.get("/healthz", response_model=Health, summary="Liveness probe", operation_id="healthz")
def healthz() -> Health:
    """Report whether the process is alive.

    Touches nothing external. A failed liveness probe restarts the container, so a check that
    depended on another service would turn that service's outage into a restart loop here.
    """
    return Health(status="ok")


@app.get(
    "/readyz",
    response_model=Health,
    summary="Readiness probe",
    operation_id="readyz",
    responses={
        503: {
            "model": ErrorResponse,
            "description": "The service has no API key configured",
        }
    },
)
def readyz() -> Health:
    """Report whether the service can accept traffic.

    Separate from liveness because a failed readiness probe only removes the container from
    rotation rather than restarting it. Without an API key configured every call to `/quote`
    would be refused, so the container has nothing useful to serve and belongs out of
    rotation until an operator fixes it — which is exactly what readiness is for, and why
    this check does not belong on `/healthz`.

    Deliberately not a call to Key Vault. The platform resolves the secret into the
    environment when the revision starts, so a missing value is a deployment fault that will
    not heal on its own, and a probe that reached the vault on every call would turn a vault
    outage into a rolling restart of a service that is running perfectly well.
    """
    if not os.environ.get("QUOTE_API_KEY"):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="no API key is configured, so the service cannot accept requests",
        )
    return Health(status="ready")


@app.get("/version", response_model=Version, summary="Build identity", operation_id="version")
def version() -> Version:
    """Report the commit the running image was built from.

    Defaults to `dev` when the build argument was not supplied. Querying this during a staged
    rollout tells you which revision served the request.
    """
    # Read per request, not at import. A module-level read is fixed at first import, long
    # before any test runs, which would make monkeypatch.setenv silently do nothing.
    return Version(git_sha=os.environ.get("GIT_SHA", "dev"))
