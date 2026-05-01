/// Measurement type: weight or volume.
enum MeasurementType { weight, volume }

/// Supported units for fridge items.
///
/// Two metric systems supported:
///   - Weight: grams (g) and ounces (oz)
///   - Volume: milliliters (ml) and gallons (gal)
///
/// All conversion goes through the base metric unit (g or ml).
enum FridgeUnit {
  // ── Weight ───────────────────────────────────────────────────────
  grams,
  ounces,
  kilograms,
  pounds,

  // ── Volume ───────────────────────────────────────────────────────
  milliliters,
  liters,
  gallons,
  cups,

  // ── Countable (no conversion) ────────────────────────────────────
  pieces;

  /// Short display label.
  String get label {
    switch (this) {
      case FridgeUnit.grams:
        return 'g';
      case FridgeUnit.ounces:
        return 'oz';
      case FridgeUnit.kilograms:
        return 'kg';
      case FridgeUnit.pounds:
        return 'lb';
      case FridgeUnit.milliliters:
        return 'ml';
      case FridgeUnit.liters:
        return 'L';
      case FridgeUnit.gallons:
        return 'gal';
      case FridgeUnit.cups:
        return 'cup';
      case FridgeUnit.pieces:
        return 'pcs';
    }
  }

  /// Full display name.
  String get displayName {
    switch (this) {
      case FridgeUnit.grams:
        return 'Grams';
      case FridgeUnit.ounces:
        return 'Ounces';
      case FridgeUnit.kilograms:
        return 'Kilograms';
      case FridgeUnit.pounds:
        return 'Pounds';
      case FridgeUnit.milliliters:
        return 'Milliliters';
      case FridgeUnit.liters:
        return 'Liters';
      case FridgeUnit.gallons:
        return 'Gallons';
      case FridgeUnit.cups:
        return 'Cups';
      case FridgeUnit.pieces:
        return 'Pieces';
    }
  }

  /// Whether this unit measures weight, volume, or is countable.
  MeasurementType? get measurementType {
    switch (this) {
      case FridgeUnit.grams:
      case FridgeUnit.ounces:
      case FridgeUnit.kilograms:
      case FridgeUnit.pounds:
        return MeasurementType.weight;
      case FridgeUnit.milliliters:
      case FridgeUnit.liters:
      case FridgeUnit.gallons:
      case FridgeUnit.cups:
        return MeasurementType.volume;
      case FridgeUnit.pieces:
        return null; // not convertible
    }
  }
}

/// Handles conversion between units.
///
/// Weight base unit: grams (g)
/// Volume base unit: milliliters (ml)
class UnitConverter {
  UnitConverter._();

  // ── Conversion factors to base unit ──────────────────────────────

  static const Map<FridgeUnit, double> _toBase = {
    // Weight → grams
    FridgeUnit.grams: 1.0,
    FridgeUnit.ounces: 28.3495,
    FridgeUnit.kilograms: 1000.0,
    FridgeUnit.pounds: 453.592,
    // Volume → milliliters
    FridgeUnit.milliliters: 1.0,
    FridgeUnit.liters: 1000.0,
    FridgeUnit.gallons: 3785.41,
    FridgeUnit.cups: 236.588,
  };

  /// Convert [value] from [from] unit to [to] unit.
  ///
  /// Both units must be the same measurement type (both weight or both volume).
  /// Returns null if conversion is not possible (e.g., grams → ml).
  static double? convert(double value, FridgeUnit from, FridgeUnit to) {
    if (from == to) return value;

    // Pieces can't be converted
    if (from == FridgeUnit.pieces || to == FridgeUnit.pieces) return null;

    // Must be same measurement type
    if (from.measurementType != to.measurementType) return null;

    final toBaseFactor = _toBase[from];
    final fromBaseFactor = _toBase[to];
    if (toBaseFactor == null || fromBaseFactor == null) return null;

    // value → base unit → target unit
    final baseValue = value * toBaseFactor;
    return baseValue / fromBaseFactor;
  }

  /// Convert to the primary metric unit (grams or ml).
  static double? toMetric(double value, FridgeUnit from) {
    if (from.measurementType == MeasurementType.weight) {
      return convert(value, from, FridgeUnit.grams);
    } else if (from.measurementType == MeasurementType.volume) {
      return convert(value, from, FridgeUnit.milliliters);
    }
    return null;
  }

  /// Convert to the primary imperial unit (ounces or gallons).
  static double? toImperial(double value, FridgeUnit from) {
    if (from.measurementType == MeasurementType.weight) {
      return convert(value, from, FridgeUnit.ounces);
    } else if (from.measurementType == MeasurementType.volume) {
      return convert(value, from, FridgeUnit.gallons);
    }
    return null;
  }

  /// Format a value with its unit label (e.g., "250 g", "1.5 gal").
  static String format(double value, FridgeUnit unit, {int decimals = 1}) {
    final formatted = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(decimals);
    return '$formatted ${unit.label}';
  }
}
