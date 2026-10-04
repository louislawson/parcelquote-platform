"""Tests for the telemetry setup, which is not an endpoint.

`test_api.py` covers the HTTP contract through the test client. These two call the
configuration function directly instead, because what matters about it happens at import time
and there is no route behind it.

Nothing here reaches Azure. `configure_azure_monitor` is replaced in both tests, so the
connection string below is never parsed and no exporter is ever started — a test that really
configured the distro would ship telemetry from the suite itself.
"""

import pytest

from parcelquote import main

# Not a real resource, and never dialled: the function that would read it is replaced in both
# tests, so only its presence in the environment is under test.
CONNECTION_STRING = "InstrumentationKey=00000000-0000-0000-0000-000000000000"


# --- telemetry configuration -------------------------------------------------------------


def test_telemetry_is_configured_when_a_connection_string_is_present(monkeypatch):
    """Asserts the call, not its effect.

    Letting the real function run would start an exporter inside the test process and send
    whatever the suite produced to a live resource. The decision under test is only whether
    the call happens, so the call is what gets recorded.
    """
    calls = []
    monkeypatch.setenv("APPLICATIONINSIGHTS_CONNECTION_STRING", CONNECTION_STRING)
    monkeypatch.setattr(main, "configure_azure_monitor", lambda **kwargs: calls.append(kwargs))

    main._configure_telemetry()

    assert len(calls) == 1


def test_telemetry_is_skipped_when_no_connection_string_is_set(monkeypatch):
    """This is the test that keeps local development working.

    `configure_azure_monitor` raises without a connection string, and the setup call runs at
    import. Unguarded, importing the module would fail — which means `poetry run pytest`,
    `poetry run uvicorn` and the `from parcelquote.main import app` at the top of `test_api.py`
    would all break on a machine that has no Application Insights resource. The guard is what
    makes the service run with nothing configured but `QUOTE_API_KEY`.
    """
    monkeypatch.delenv("APPLICATIONINSIGHTS_CONNECTION_STRING", raising=False)
    monkeypatch.setattr(
        main,
        "configure_azure_monitor",
        lambda **kwargs: pytest.fail("telemetry was configured with no connection string set"),
    )

    main._configure_telemetry()


def test_the_module_does_not_bind_a_fastapi_name(monkeypatch):
    """Guards the subtlest part of the setup, which once shipped broken.

    The instrumentor does not wrap a method, it rebinds one — `_instrument` sets
    `fastapi.FastAPI = _InstrumentedFastAPI`. A module-level `from fastapi import FastAPI`
    therefore captures the original class before `configure_azure_monitor` runs, and the app is
    built unpatched: no request span is ever produced, while dependency and metric telemetry
    flows normally, so nothing looks wrong. `main` builds the app as `fastapi.FastAPI` to get
    the attribute lookup, and this asserts the tempting shorthand has not come back.

    It will also fail if the name is imported for an annotation and never used to construct,
    which is a false positive — but one that fails loudly, where the real fault is silent.
    """
    assert not hasattr(main, "FastAPI")
