# parcelquote

A shipping quote API. Given a parcel's dimensions, weight and destination zone, it returns a
price and shows how that price was reached.

The service is deliberately small. It exists to be built, tested, containerised and released by
the surrounding platform — see the [repository README](../README.md) for that story.

## Pricing model

Carriers do not charge for mass alone. A large, light parcel occupies space that could have
carried something heavier, so freight is priced on **chargeable weight**: the greater of the
actual weight and the volumetric weight.

    volumetric weight = (length × width × height) / 5000

The 5000 divisor is the common air freight convention. Chargeable weight then selects a weight
band, and a destination zone multiplier is applied to the band rate.

Bands, zones and rates are defined as constants in `src/parcelquote/pricing.py`. That module is
pure — no framework imports, no I/O, no globals — so the pricing rules can be tested in
isolation and read without tracing HTTP handlers.

## API

| Method | Path       | Purpose                                                                             |
| ------ | ---------- | ----------------------------------------------------------------------------------- |
| POST   | `/quote`   | Price a parcel. Returns the price, the chargeable weight, and which weight was used |
| GET    | `/healthz` | Liveness. Confirms the process is running. Touches nothing external                 |
| GET    | `/readyz`  | Readiness. Confirms the service can accept traffic                                  |
| GET    | `/version` | Build identity — the commit the image was built from                                |

Liveness and readiness are separate endpoints because the runtime treats them differently. A
failed liveness probe restarts the container; a failed readiness probe only removes it from
rotation. Collapsing them into one check means a slow dependency gets the process killed rather
than briefly taken out of service.

Invalid input is rejected by the request model rather than by hand-written checks, so malformed
requests return `422` with a description of the offending field.

A parcel too heavy to carry is a separate case. The request is well formed, so it is not a
validation failure; it asks for something outside the product. Those are rejected with `400`
and a single sentence explaining why. The two statuses therefore carry different body shapes —
`422` returns a list of per-field errors, `400` returns one message — which is the reason they
are kept apart rather than collapsed into one code.

```bash
curl -X POST http://localhost:8000/quote \
  -H 'Content-Type: application/json' \
  -d '{"length_cm": 40, "width_cm": 30, "height_cm": 20, "weight_kg": 2.5, "zone": "uk"}'
```

The response repeats the weights behind the price, so a caller can see which one determined the
charge:

```json
{
  "price": "9.99",
  "actual_weight_kg": "2.5",
  "volumetric_weight_kg": "4.8",
  "chargeable_weight_kg": "4.8",
  "zone": "uk"
}
```

The price and the weights cross the wire as JSON **strings**, not numbers. Most clients parse a
JSON number into an IEEE 754 float, which reintroduces on the caller's side the inexactness that
`pricing.py` uses `Decimal` to avoid. Strings also preserve trailing zeros, so a price of `9.90`
arrives as `9.90` rather than `9.9` — the difference between a price a customer can read and one
that needs reformatting.

Requests are more forgiving. Dimensions and weights may be sent as JSON numbers or as strings;
both are parsed straight to `Decimal` without passing through a float.

## Local development

Requires Python 3.12 and [Poetry](https://python-poetry.org/).

```bash
poetry install
```

```bash
poetry run uvicorn parcelquote.main:app --reload
```

Interactive documentation is then served at `http://localhost:8000/docs`.

Run the tests and the linter:

```bash
poetry run pytest
```

```bash
poetry run ruff check .
```

`poetry.lock` is committed. After changing dependencies, re-run `poetry lock` — `poetry check
--lock` fails if the lock file and `pyproject.toml` have drifted apart.

## Container

The image is multi-stage: Poetry resolves and installs dependencies in a builder stage, and only
the resulting virtual environment and application source are copied into the final image. Poetry
itself is not present at runtime, and the process runs as a non-root user.

```bash
docker build -t parcelquote:dev --build-arg GIT_SHA=$(git rev-parse --short HEAD) .
```

```bash
docker run --rm -p 8000:8000 parcelquote:dev
```

`GIT_SHA` defaults to `dev` when the argument is omitted. The pipeline passes the real commit,
which is what makes `/version` useful during a staged rollout: query the endpoint and you know
which revision answered.

## Layout

    pyproject.toml          Dependencies, and ruff and pytest configuration
    poetry.lock             Pinned dependency graph — committed deliberately
    Dockerfile
    src/parcelquote/
      pricing.py            Pure pricing logic
      main.py               FastAPI application, request and response models
    tests/
      test_pricing.py       Unit tests for the pricing rules
      test_api.py           Endpoint tests through the FastAPI test client
