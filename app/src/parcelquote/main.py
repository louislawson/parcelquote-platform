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
from decimal import Decimal
from typing import Final

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from parcelquote.pricing import Zone
from parcelquote.pricing import quote as price_parcel

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


@app.post(
    "/quote",
    response_model=QuoteResponse,
    summary="Request a quote for a parcel",
    response_description="The quote for the parcel",
    responses={
        400: {
            "model": ErrorResponse,
            "description": "The parcel exceeds the maximum chargeable weight",
        }
    },
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


@app.get("/readyz", response_model=Health, summary="Readiness probe", operation_id="readyz")
def readyz() -> Health:
    """Report whether the service can accept traffic.

    Separate from liveness because a failed readiness probe only removes the container from
    rotation. This is where a dependency check belongs; the service currently has none.
    """
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
