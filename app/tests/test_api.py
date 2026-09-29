"""Endpoint tests, through the FastAPI test client.

These test the HTTP contract, not the tariff. `test_pricing.py` already proves the arithmetic
against every band boundary, so repeating it here would only couple the suite to the price
list twice over. What matters at this layer is what crosses the wire: the status codes, the
JSON shape, and the fact that money arrives as a string rather than a float.

One price is asserted end to end — the worked example — so that a route wired to the wrong
function, or to no pricing at all, cannot pass.
"""

import pytest
from fastapi.testclient import TestClient

from parcelquote.main import app

# 40 x 30 x 20 cm is 4.8 kg volumetric, which beats the 0.5 kg actual weight and lands in the
# 5 kg band at 9.99. The eu multiplier of 1.5 then gives 14.985, which rounds to 14.99 only
# under ROUND_HALF_UP. One request exercising the crossover, a mid band and the rounding mode.
WORKED_EXAMPLE = {
    "length_cm": 40,
    "width_cm": 30,
    "height_cm": 20,
    "weight_kg": 0.5,
    "zone": "eu",
}


API_KEY = "test-key-not-a-real-one"


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("QUOTE_API_KEY", API_KEY)
    return TestClient(app, headers={"X-API-Key": API_KEY})


@pytest.fixture
def anonymous_client(monkeypatch):
    """A correctly configured service, and a caller sending no key."""
    monkeypatch.setenv("QUOTE_API_KEY", API_KEY)
    return TestClient(app)


# --- a successful quote ------------------------------------------------------------------


def test_valid_quote_returns_200(client):
    assert client.post("/quote", json=WORKED_EXAMPLE).status_code == 200


def test_quote_prices_the_worked_example(client):
    body = client.post("/quote", json=WORKED_EXAMPLE).json()
    assert body["price"] == "14.99"


def test_price_crosses_the_wire_as_a_string(client):
    """A JSON number becomes a float in most clients, which is what Decimal exists to avoid.

    Asserting the value alone would pass just as happily on 14.99 the number, so assert the
    type. This is the test that fails if someone "tidies up" the response model to a float.
    """
    body = client.post("/quote", json=WORKED_EXAMPLE).json()
    assert isinstance(body["price"], str)


def test_quote_reports_the_weights_behind_the_price(client):
    body = client.post("/quote", json=WORKED_EXAMPLE).json()
    assert body["actual_weight_kg"] == "0.5"
    assert body["volumetric_weight_kg"] == "4.8"
    assert body["chargeable_weight_kg"] == "4.8"


def test_quote_echoes_the_zone(client):
    assert client.post("/quote", json=WORKED_EXAMPLE).json()["zone"] == "eu"


def test_decimal_arrives_from_a_json_float_without_contamination(client):
    """0.1 as a JSON float is not exactly 0.1 in binary.

    Pydantic parses it straight to Decimal, so pricing.py never sees a float. A parcel of
    3 x 0.1 kg dimensions would price differently if it did.
    """
    response = client.post(
        "/quote",
        json={**WORKED_EXAMPLE, "weight_kg": 0.1},
    )
    assert response.status_code == 200
    assert response.json()["actual_weight_kg"] == "0.1"


# --- authentication ----------------------------------------------------------------------


def test_quote_without_a_key_is_refused(anonymous_client):
    assert anonymous_client.post("/quote", json=WORKED_EXAMPLE).status_code == 401


def test_quote_with_the_wrong_key_is_refused(anonymous_client):
    response = anonymous_client.post(
        "/quote", json=WORKED_EXAMPLE, headers={"X-API-Key": "not-the-key"}
    )
    assert response.status_code == 401


def test_a_non_ascii_key_is_refused_rather_than_crashing(anonymous_client):
    """secrets.compare_digest raises TypeError on any str above ASCII.

    Starlette decodes headers as latin-1, so one byte in a header would turn a 401 into a
    500 for anyone who cared to send it. The comparison encodes both sides to bytes first.
    Sent as bytes because httpx refuses to encode a non-ASCII str header at all.
    """
    response = anonymous_client.post(
        "/quote", json=WORKED_EXAMPLE, headers={b"X-API-Key": "ké".encode("latin-1")}
    )
    assert response.status_code == 401


def test_quote_is_unavailable_when_no_key_is_configured(client, monkeypatch):
    """503, not 401. An unconfigured server is the operator's fault, not the caller's.

    Deleted after the client is built, which only works because the key is read per
    request — the same property the /version tests pin.
    """
    monkeypatch.delenv("QUOTE_API_KEY", raising=False)
    assert client.post("/quote", json=WORKED_EXAMPLE).status_code == 503


def test_an_unconfigured_service_answers_503_whatever_the_caller_sent(
    anonymous_client, monkeypatch
):
    """The same fault has to produce the same answer.

    This is what auto_error=False buys. With FastAPI rejecting a header-less request before
    the dependency runs, this case would be 401 while the one above stayed 503 — the same
    broken server blaming the caller or the operator depending on what arrived.
    """
    monkeypatch.delenv("QUOTE_API_KEY", raising=False)
    assert anonymous_client.post("/quote", json=WORKED_EXAMPLE).status_code == 503


# --- field validation, handled by the request model --------------------------------------


@pytest.mark.parametrize("field", ["length_cm", "width_cm", "height_cm", "weight_kg", "zone"])
def test_missing_field_is_rejected(client, field):
    payload = {k: v for k, v in WORKED_EXAMPLE.items() if k != field}
    response = client.post("/quote", json=payload)
    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"] == ["body", field]


@pytest.mark.parametrize("field", ["length_cm", "width_cm", "height_cm", "weight_kg"])
@pytest.mark.parametrize("value", [0, -1])
def test_non_positive_dimensions_are_rejected(client, field, value):
    response = client.post("/quote", json={**WORKED_EXAMPLE, field: value})
    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"] == ["body", field]


def test_unknown_zone_is_rejected(client):
    response = client.post("/quote", json={**WORKED_EXAMPLE, "zone": "mars"})
    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"] == ["body", "zone"]


def test_non_numeric_dimension_is_rejected(client):
    response = client.post("/quote", json={**WORKED_EXAMPLE, "length_cm": "wide"})
    assert response.status_code == 422


def test_validation_failure_names_the_offending_field(client):
    """422 bodies are a list of errors, one per field, each locating itself.

    Worth pinning: an integrator builds their error handling against this shape, and the
    business-rule rejection below deliberately uses a different one.
    """
    response = client.post("/quote", json={**WORKED_EXAMPLE, "weight_kg": -1})
    detail = response.json()["detail"]
    assert isinstance(detail, list)
    assert detail[0]["loc"] == ["body", "weight_kg"]
    assert detail[0]["type"] == "greater_than"


# --- the business rule the request model cannot express ----------------------------------


def test_overweight_parcel_is_rejected_with_400(client):
    """A 1 metre cube is 200 kg volumetric, whatever it actually weighs.

    The ceiling depends on computed volumetric weight, so it cannot be a field constraint.
    400 rather than 422: the request is well formed, it just asks for something outside the
    product.
    """
    response = client.post(
        "/quote",
        json={
            "length_cm": 100,
            "width_cm": 100,
            "height_cm": 100,
            "weight_kg": 1,
            "zone": "uk",
        },
    )
    assert response.status_code == 400
    assert "exceeds" in response.json()["detail"]


def test_heavy_parcel_within_the_ceiling_is_still_priced(client):
    """Guards the boundary from the other side, so a too-eager rejection is caught."""
    response = client.post(
        "/quote",
        json={**WORKED_EXAMPLE, "weight_kg": 50, "zone": "uk"},
    )
    assert response.status_code == 200


# --- probes ------------------------------------------------------------------------------


@pytest.mark.parametrize(("path", "status"), [("/healthz", "ok"), ("/readyz", "ready")])
def test_probes_report_their_status(client, path, status):
    response = client.get(path)
    assert response.status_code == 200
    assert response.json() == {"status": status}


def test_readyz_is_not_ready_without_a_key(client, monkeypatch):
    """Readiness removes the container from rotation; liveness would restart it.

    With no key configured every call to /quote is refused, so the container has nothing
    useful to serve and belongs out of rotation until an operator fixes it.
    """
    monkeypatch.delenv("QUOTE_API_KEY", raising=False)
    assert client.get("/readyz").status_code == 503
    assert client.get("/healthz").status_code == 200



# --- build identity ----------------------------------------------------------------------


def test_version_returns_the_injected_sha(client, monkeypatch):
    """Reads the environment per request.

    Set at import time instead, this passes only by accident of import order, and fails once
    another test imports the module first.
    """
    monkeypatch.setenv("GIT_SHA", "abc1234")
    assert client.get("/version").json() == {"git_sha": "abc1234"}


def test_version_defaults_to_dev(client, monkeypatch):
    monkeypatch.delenv("GIT_SHA", raising=False)
    assert client.get("/version").json() == {"git_sha": "dev"}


def test_version_reflects_a_change_within_one_session(client, monkeypatch):
    """Two values in one test. A cached module-level read passes the test above but not this."""
    monkeypatch.setenv("GIT_SHA", "first")
    assert client.get("/version").json()["git_sha"] == "first"
    monkeypatch.setenv("GIT_SHA", "second")
    assert client.get("/version").json()["git_sha"] == "second"
