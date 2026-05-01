import 'package:flutter_test/flutter_test.dart';
import 'package:fridge_app/models/units.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════
  // FridgeUnit properties
  // ═══════════════════════════════════════════════════════════════════

  group('FridgeUnit', () {
    test('all units have non-empty labels and display names', () {
      for (final unit in FridgeUnit.values) {
        expect(unit.label.isNotEmpty, true);
        expect(unit.displayName.isNotEmpty, true);
      }
    });

    test('weight units have weight measurement type', () {
      expect(FridgeUnit.grams.measurementType, MeasurementType.weight);
      expect(FridgeUnit.ounces.measurementType, MeasurementType.weight);
      expect(FridgeUnit.kilograms.measurementType, MeasurementType.weight);
      expect(FridgeUnit.pounds.measurementType, MeasurementType.weight);
    });

    test('volume units have volume measurement type', () {
      expect(FridgeUnit.milliliters.measurementType, MeasurementType.volume);
      expect(FridgeUnit.liters.measurementType, MeasurementType.volume);
      expect(FridgeUnit.gallons.measurementType, MeasurementType.volume);
      expect(FridgeUnit.cups.measurementType, MeasurementType.volume);
    });

    test('pieces has null measurement type', () {
      expect(FridgeUnit.pieces.measurementType, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // UnitConverter
  // ═══════════════════════════════════════════════════════════════════

  group('UnitConverter', () {
    group('weight conversions', () {
      test('grams to ounces', () {
        final oz = UnitConverter.convert(
          100,
          FridgeUnit.grams,
          FridgeUnit.ounces,
        );
        expect(oz, isNotNull);
        expect(oz!, closeTo(3.527, 0.01));
      });

      test('ounces to grams', () {
        final g = UnitConverter.convert(1, FridgeUnit.ounces, FridgeUnit.grams);
        expect(g, isNotNull);
        expect(g!, closeTo(28.35, 0.01));
      });

      test('kilograms to grams', () {
        final g = UnitConverter.convert(
          2,
          FridgeUnit.kilograms,
          FridgeUnit.grams,
        );
        expect(g, isNotNull);
        expect(g!, closeTo(2000, 0.01));
      });

      test('pounds to ounces', () {
        final oz = UnitConverter.convert(
          1,
          FridgeUnit.pounds,
          FridgeUnit.ounces,
        );
        expect(oz, isNotNull);
        expect(oz!, closeTo(16, 0.1));
      });

      test('kilograms to pounds', () {
        final lb = UnitConverter.convert(
          1,
          FridgeUnit.kilograms,
          FridgeUnit.pounds,
        );
        expect(lb, isNotNull);
        expect(lb!, closeTo(2.205, 0.01));
      });
    });

    group('volume conversions', () {
      test('milliliters to gallons', () {
        final gal = UnitConverter.convert(
          3785.41,
          FridgeUnit.milliliters,
          FridgeUnit.gallons,
        );
        expect(gal, isNotNull);
        expect(gal!, closeTo(1.0, 0.01));
      });

      test('gallons to milliliters', () {
        final ml = UnitConverter.convert(
          1,
          FridgeUnit.gallons,
          FridgeUnit.milliliters,
        );
        expect(ml, isNotNull);
        expect(ml!, closeTo(3785.41, 1));
      });

      test('liters to cups', () {
        final cups = UnitConverter.convert(
          1,
          FridgeUnit.liters,
          FridgeUnit.cups,
        );
        expect(cups, isNotNull);
        expect(cups!, closeTo(4.227, 0.01));
      });

      test('liters to milliliters', () {
        final ml = UnitConverter.convert(
          2.5,
          FridgeUnit.liters,
          FridgeUnit.milliliters,
        );
        expect(ml, isNotNull);
        expect(ml!, closeTo(2500, 0.01));
      });
    });

    group('edge cases', () {
      test('same unit returns same value', () {
        final result = UnitConverter.convert(
          42,
          FridgeUnit.grams,
          FridgeUnit.grams,
        );
        expect(result, 42);
      });

      test('cross-type conversion returns null (grams to ml)', () {
        final result = UnitConverter.convert(
          100,
          FridgeUnit.grams,
          FridgeUnit.milliliters,
        );
        expect(result, isNull);
      });

      test('pieces conversion returns null', () {
        final result = UnitConverter.convert(
          5,
          FridgeUnit.pieces,
          FridgeUnit.grams,
        );
        expect(result, isNull);
      });

      test('conversion to pieces returns null', () {
        final result = UnitConverter.convert(
          100,
          FridgeUnit.grams,
          FridgeUnit.pieces,
        );
        expect(result, isNull);
      });
    });

    group('toMetric', () {
      test('converts weight to grams', () {
        final g = UnitConverter.toMetric(2, FridgeUnit.ounces);
        expect(g, isNotNull);
        expect(g!, closeTo(56.699, 0.01));
      });

      test('converts volume to ml', () {
        final ml = UnitConverter.toMetric(1, FridgeUnit.gallons);
        expect(ml, isNotNull);
        expect(ml!, closeTo(3785.41, 1));
      });

      test('pieces returns null', () {
        expect(UnitConverter.toMetric(5, FridgeUnit.pieces), isNull);
      });
    });

    group('toImperial', () {
      test('converts weight to ounces', () {
        final oz = UnitConverter.toImperial(500, FridgeUnit.grams);
        expect(oz, isNotNull);
        expect(oz!, closeTo(17.637, 0.01));
      });

      test('converts volume to gallons', () {
        final gal = UnitConverter.toImperial(1000, FridgeUnit.milliliters);
        expect(gal, isNotNull);
        expect(gal!, closeTo(0.264, 0.01));
      });
    });

    group('format', () {
      test('formats whole numbers without decimals', () {
        expect(UnitConverter.format(250, FridgeUnit.grams), '250 g');
      });

      test('formats decimals with specified precision', () {
        expect(UnitConverter.format(1.5, FridgeUnit.gallons), '1.5 gal');
      });

      test('formats pieces', () {
        expect(UnitConverter.format(3, FridgeUnit.pieces), '3 pcs');
      });
    });
  });
}
