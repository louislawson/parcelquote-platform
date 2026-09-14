"""Unit tests for the pricing rules.

Written against the tariff agreed before any implementation existed, so these tests are the
specification rather than a description of whatever the code happens to do.

Every monetary assertion compares an exact Decimal. pytest.approx is deliberately absent: a
tolerant comparison passes just as happily on a float implementation carrying the rounding
error that Decimal exists to prevent, which would make the whole exercise pointless.
"""

from decimal import Decimal

import pytest

from parcelquote.pricing import (
    MAX_CHARGEABLE_KG,
    WEIGHT_BANDS,
    Zone,
    chargeable_weight,
    price_for,
    quote,
    volumetric_weight,
)

D = Decimal

# A parcel large enough that its volumetric weight (4.8 kg) exceeds a light actual weight.
BULKY = {"length_cm": D("40"), "width_cm": D("30"), "height_cm": D("20")}

# A parcel small enough that actual weight always wins.
COMPACT = {"length_cm": D("10"), "width_cm": D("10"), "height_cm": D("10")}


# --- volumetric weight ------------------------------------------------------------------


@pytest.mark.parametrize(
    ("length", "width", "height", "expected"),
    [
        (D("40"), D("30"), D("20"), D("4.8")),
        (D("10"), D("10"), D("10"), D("0.2")),
        (D("50"), D("40"), D("30"), D("12")),
    ],
)
def test_volumetric_weight_divides_by_5000(length, width, height, expected):
    assert volumetric_weight(length, width, height) == expected


# --- chargeable weight ------------------------------------------------------------------


@pytest.mark.parametrize(
    ("actual", "volumetric", "expected"),
    [
        (D("5.0"), D("4.8"), D("5.0")),
        (D("0.5"), D("4.8"), D("4.8")),
        (D("4.8"), D("4.8"), D("4.8")),
    ],
)
def test_chargeable_weight_takes_the_greater(actual, volumetric, expected):
    """A reversed comparison here still returns a plausible price, so test it directly."""
    assert chargeable_weight(actual, volumetric) == expected


# --- weight bands -----------------------------------------------------------------------


@pytest.mark.parametrize(
    ("weight", "expected"),
    [
        (D("0.001"), D("4.99")),
        (D("1.000"), D("4.99")),
        (D("1.001"), D("6.49")),
        (D("2.000"), D("6.49")),
        (D("2.001"), D("9.99")),
        (D("5.000"), D("9.99")),
        (D("5.001"), D("14.99")),
        (D("10.000"), D("14.99")),
        (D("10.001"), D("24.99")),
        (D("20.000"), D("24.99")),
    ],
)
def test_band_upper_bounds_are_inclusive(weight, expected):
    assert price_for(weight) == expected


def test_weight_bands_are_strictly_ascending():
    """First match wins, so a band inserted out of order makes everything above unreachable."""
    limits = [band.max_kg for band in WEIGHT_BANDS]
    assert limits == sorted(limits)
    assert len(set(limits)) == len(limits)


# --- heavy tier -------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("weight", "expected"),
    [
        (D("20.001"), D("26.19")),
        (D("21.000"), D("26.19")),
        (D("21.001"), D("27.39")),
        (D("25.000"), D("30.99")),
        (D("50.000"), D("60.99")),
    ],
)
def test_heavy_tier_charges_whole_kilograms(weight, expected):
    """20.001 and 21.000 both cost one extra kg.

    An implementation written as int(excess) + 1 passes the first and fails the second,
    billing exactly 21 kg as two additional kilograms.
    """
    assert price_for(weight) == expected


def test_maximum_weight_sits_above_the_banded_table():
    assert MAX_CHARGEABLE_KG > WEIGHT_BANDS[-1].max_kg


def test_weight_above_the_maximum_is_rejected():
    with pytest.raises(ValueError, match="exceeds"):
        price_for(MAX_CHARGEABLE_KG + D("0.001"))


# --- zones and rounding -----------------------------------------------------------------


@pytest.mark.parametrize(
    ("zone", "expected"),
    [
        (Zone.UK, D("9.99")),
        (Zone.EU, D("14.99")),
        (Zone.WORLD, D("23.98")),
    ],
)
def test_zone_multiplier_applies_to_the_total(zone, expected):
    result = quote(**BULKY, weight_kg=D("0.5"), zone=zone)
    assert result.price == expected


def test_rounding_is_half_up_not_half_even():
    """4.99 x 1.5 = 7.485 exactly. ROUND_HALF_EVEN, Python's default, would give 7.48."""
    result = quote(**COMPACT, weight_kg=D("1"), zone=Zone.EU)
    assert result.price == D("7.49")


def test_price_is_quantized_to_two_decimal_places():
    """Decimal compares numerically, so 9.990 == 9.99. Only the exponent proves quantize ran."""
    result = quote(**BULKY, weight_kg=D("0.5"), zone=Zone.UK)
    assert result.price.as_tuple().exponent == -2


# --- quote composition ------------------------------------------------------------------


def test_quote_reports_the_weights_behind_the_price():
    result = quote(**BULKY, weight_kg=D("0.5"), zone=Zone.UK)
    assert result.actual_weight_kg == D("0.5")
    assert result.volumetric_weight_kg == D("4.8")
    assert result.chargeable_weight_kg == D("4.8")


def test_quote_reports_weights_when_actual_wins():
    result = quote(**BULKY, weight_kg=D("5.0"), zone=Zone.UK)
    assert result.actual_weight_kg == D("5.0")
    assert result.volumetric_weight_kg == D("4.8")
    assert result.chargeable_weight_kg == D("5.0")


def test_oversized_parcel_is_rejected_on_volumetric_weight():
    """A 1 metre cube weighs 200 kg volumetrically, whatever it actually weighs."""
    with pytest.raises(ValueError, match="exceeds"):
        quote(
            length_cm=D("100"),
            width_cm=D("100"),
            height_cm=D("100"),
            weight_kg=D("1"),
            zone=Zone.UK,
        )


@pytest.mark.parametrize(
    ("length", "width", "height", "weight"),
    [
        (D("0"), D("30"), D("20"), D("1")),
        (D("40"), D("0"), D("20"), D("1")),
        (D("40"), D("30"), D("0"), D("1")),
        (D("-1"), D("30"), D("20"), D("1")),
        (D("40"), D("30"), D("20"), D("0")),
        (D("40"), D("30"), D("20"), D("-1")),
    ],
)
def test_non_positive_inputs_are_rejected(length, width, height, weight):
    with pytest.raises(ValueError):
        quote(
            length_cm=length,
            width_cm=width,
            height_cm=height,
            weight_kg=weight,
            zone=Zone.UK,
        )
