import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/app/data_licenses.dart';

void main() {
  test('dataset licenses are listed on the license page', () async {
    registerDataLicenses();
    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }
    for (final (name, _) in dataLicenses) {
      expect(packages, contains('GUDORY data: $name'));
    }
    expect(dataLicenses.map((e) => e.$1).join(), contains('CADB'));
    expect(dataLicenses.map((e) => e.$1).join(), contains('Open Images'));
  });
}
