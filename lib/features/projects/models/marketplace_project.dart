/// Marketplace project — a row from `public.projects` flagged as
/// `is_listed_in_marketplace = true`. Surfaced on the Explore tab so
/// investors can browse and request consultations on new offerings.
///
/// Admins manage these via Supabase Studio: flip the flag, set the
/// tagline / deadline / sort order, and the next app launch shows it.
class MarketplaceProject {
  final String id;
  final String name;
  final String tagline;
  final String location;
  final String tier;
  final String? cropType;
  final int totalUnits;
  final int unitsAvailable;
  final double pricePerUnit;
  final double? acreageAcres;
  final double expectedAnnualReturnPct;
  final DateTime? subscriptionDeadline;
  final String? marketplaceImage;
  final String llpStatus;

  const MarketplaceProject({
    required this.id,
    required this.name,
    required this.tagline,
    required this.location,
    required this.tier,
    required this.totalUnits,
    required this.unitsAvailable,
    required this.pricePerUnit,
    required this.expectedAnnualReturnPct,
    required this.llpStatus,
    this.cropType,
    this.acreageAcres,
    this.subscriptionDeadline,
    this.marketplaceImage,
  });

  factory MarketplaceProject.fromSupabase(Map<String, dynamic> r) {
    return MarketplaceProject(
      id: (r['id'] ?? '') as String,
      name: (r['name'] ?? '') as String,
      tagline: (r['tagline'] ?? '') as String,
      location: _composeLocation(r),
      tier: (r['tier'] ?? '') as String,
      cropType: r['crop_type'] as String?,
      totalUnits: (r['total_units'] as num?)?.toInt() ?? 0,
      unitsAvailable: (r['units_available'] as num?)?.toInt() ?? 0,
      pricePerUnit: (r['price_per_unit'] as num?)?.toDouble() ?? 0.0,
      acreageAcres: (r['acreage_acres'] as num?)?.toDouble(),
      expectedAnnualReturnPct:
          (r['expected_annual_return_pct'] as num?)?.toDouble() ??
              (r['annual_yield_pct'] as num?)?.toDouble() ??
              0.0,
      subscriptionDeadline: _parseDate(r['subscription_deadline']),
      marketplaceImage: r['marketplace_image'] as String?,
      llpStatus: (r['status'] ?? '') as String,
    );
  }

  /// True if [subscriptionDeadline] has passed.
  bool get isClosed =>
      subscriptionDeadline != null &&
      subscriptionDeadline!.isBefore(DateTime.now());

  /// True if it's a fresh listing (no units issued yet).
  bool get isNotYetStarted => unitsAvailable == totalUnits;
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  try {
    return DateTime.parse(v.toString());
  } catch (_) {
    return null;
  }
}

String _composeLocation(Map<String, dynamic> r) {
  final city = (r['city'] ?? '') as String;
  final state = (r['state'] ?? '') as String;
  final composed = [city, state].where((s) => s.isNotEmpty).join(', ');
  if (composed.isNotEmpty) return composed;
  return (r['address_line1'] ?? '') as String;
}
