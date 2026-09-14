"""Shipping quote pricing rules.

Prices a parcel on chargeable weight: the greater of its actual weight and its volumetric
weight, the latter being the space it occupies expressed as a weight. A large, light parcel is
charged for the capacity it denies to heavier freight.

Banded rates apply up to 20 kg. Above that a per-kilogram surcharge is added, with any part of
a kilogram charged as a whole one, to a ceiling of 50 kg. A destination zone multiplier is
applied to the total.

This module is pure: no framework imports, no I/O, no mutable module state. Money is Decimal
throughout and is rounded exactly once, in `quote`, after the zone multiplier is applied.
"""

from collections.abc import Mapping
from dataclasses import dataclass
from decimal import ROUND_CEILING, ROUND_HALF_UP, Decimal
from enum import StrEnum
from typing import Final, NamedTuple

# Cubic centimetres treated as one kilogram of capacity. 5000 is the air freight convention;
# road freight commonly uses 6000, which prices bulky parcels more cheaply.
VOLUMETRIC_DIVISOR: Final = Decimal("5000")


class WeightBand(NamedTuple):
    """A flat price for any chargeable weight up to and including `max_kg`."""

    max_kg: Decimal
    base_price: Decimal


# Ascending, upper bound inclusive, first match wins. The order is load-bearing: a band
# inserted out of sequence would make every heavier band unreachable, silently.
WEIGHT_BANDS: Final = (
    WeightBand(Decimal("1"), Decimal("4.99")),
    WeightBand(Decimal("2"), Decimal("6.49")),
    WeightBand(Decimal("5"), Decimal("9.99")),
    WeightBand(Decimal("10"), Decimal("14.99")),
    WeightBand(Decimal("20"), Decimal("24.99")),
)

# Anchors the heavy tier, so neither the threshold nor its base price is ever restated.
_TOP_BAND: Final = WEIGHT_BANDS[-1]

# Above the table's implied rate of 1.00 per kg between the 10 kg and 20 kg bands, because
# heavier goods cost more per kilogram to handle.
HEAVY_RATE_PER_KG: Final = Decimal("1.20")

# Beyond this a parcel leaves the parcel network entirely and a pallet quote is a different
# product, so it is rejected rather than priced.
MAX_CHARGEABLE_KG: Final = Decimal("50")


class Zone(StrEnum):
    """Destination zones.

    A StrEnum so a raw string arriving from JSON compares and hashes as the member itself,
    which keeps the multiplier lookup free of a conversion layer.
    """

    UK = "uk"
    EU = "eu"
    WORLD = "world"


# Applied to the banded total, not to individual bands.
ZONE_MULTIPLIERS: Final[Mapping[Zone, Decimal]] = {
    Zone.UK: Decimal("1.0"),
    Zone.EU: Decimal("1.5"),
    Zone.WORLD: Decimal("2.4"),
}


def volumetric_weight(length_cm: Decimal, width_cm: Decimal, height_cm: Decimal) -> Decimal:
    """Weight the parcel is charged at for the space it occupies.

    Dimensions in centimetres. Deliberately unvalidated: callers arrive through `quote`, which
    rejects non-positive input before any arithmetic runs.
    """
    return length_cm * width_cm * height_cm / VOLUMETRIC_DIVISOR


def chargeable_weight(actual_kg: Decimal, volumetric_kg: Decimal) -> Decimal:
    """Carriers charge for whichever is greater."""
    return max(actual_kg, volumetric_kg)


def price_for(chargeable_kg: Decimal) -> Decimal:
    """Price for a chargeable weight, before the zone multiplier.

    Band upper bounds are inclusive: exactly 2 kg falls in the 2 kg band, and 2.001 kg falls
    in the next one up. Above the top band a surcharge applies per whole kilogram of excess,
    so 20.001 kg and 21 kg both cost one additional kilogram.

    The returned value is not rounded. `quote` applies the zone multiplier and quantizes once.

    Raises:
        ValueError: the chargeable weight exceeds MAX_CHARGEABLE_KG.
    """
    if chargeable_kg > MAX_CHARGEABLE_KG:
        raise ValueError(
            f"chargeable weight {chargeable_kg} kg exceeds the maximum of {MAX_CHARGEABLE_KG} kg"
        )

    for band in WEIGHT_BANDS:
        if chargeable_kg <= band.max_kg:
            return band.base_price

    excess_kg = chargeable_kg - _TOP_BAND.max_kg
    whole_kg = excess_kg.to_integral_value(rounding=ROUND_CEILING)
    return _TOP_BAND.base_price + HEAVY_RATE_PER_KG * whole_kg


@dataclass(frozen=True)
class Quote:
    """A priced quote, with the weights that produced it.

    Both weights are reported so a caller can see why the parcel was priced as it was.
    Chargeable weight is whichever of the two was greater.
    """

    price: Decimal
    actual_weight_kg: Decimal
    volumetric_weight_kg: Decimal
    chargeable_weight_kg: Decimal
    zone: Zone


def quote(
    *,
    length_cm: Decimal,
    width_cm: Decimal,
    height_cm: Decimal,
    weight_kg: Decimal,
    zone: Zone,
) -> Quote:
    """Price a parcel for a destination zone.

    Dimensions in centimetres, weight in kilograms. The returned price has the zone multiplier
    applied and is quantized to two decimal places with ROUND_HALF_UP, which is the only
    rounding performed anywhere in this module.

    Keyword-only because three of the five arguments are interchangeable dimensions, and a
    transposed positional call would still return an entirely plausible price.

    Raises:
        ValueError: a dimension or the weight is zero or negative, or the chargeable weight
            exceeds MAX_CHARGEABLE_KG.
    """
    if any(value <= 0 for value in (length_cm, width_cm, height_cm, weight_kg)):
        raise ValueError("dimensions and weight must be greater than zero")

    volumetric = volumetric_weight(length_cm, width_cm, height_cm)
    chargeable = chargeable_weight(weight_kg, volumetric)
    base = price_for(chargeable)
    price = (base * ZONE_MULTIPLIERS[zone]).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

    return Quote(
        price=price,
        actual_weight_kg=weight_kg,
        volumetric_weight_kg=volumetric,
        chargeable_weight_kg=chargeable,
        zone=zone,
    )
