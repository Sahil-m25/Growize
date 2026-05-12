import 'package:intl/intl.dart';

/// Indian currency formatting helpers.
///
/// Rule: show in Lakhs until amount >= 1 Cr, then show in Crores.
/// Always prefixed with "Rs." (rendered as ₹).
///
/// Examples:
///   500000     → "₹5.00 L"
///   9999999    → "₹99.99 L"
///   10000000   → "₹1.00 Cr"
///   200000000  → "₹20.00 Cr"
///   0          → "₹0"
class Money {
  static final NumberFormat _two = NumberFormat('#,##,##0.00', 'en_IN');
  static final NumberFormat _whole = NumberFormat('#,##,##0', 'en_IN');

  static const double _lakh = 100000;
  static const double _crore = 10000000;

  /// Indian Lakh/Crore formatter. Shows L until 1 Cr, then Cr.
  /// `inline` removes the space (e.g. "₹20.00Cr" instead of "₹20.00 Cr").
  static String inr(num amount, {bool inline = false}) {
    if (amount == 0) return '₹0';
    final abs = amount.abs();
    final sign = amount < 0 ? '-' : '';
    final sep = inline ? '' : ' ';
    if (abs >= _crore) {
      return '$sign₹${_two.format(abs / _crore)}${sep}Cr';
    }
    if (abs >= _lakh) {
      return '$sign₹${_two.format(abs / _lakh)}${sep}L';
    }
    return '$sign₹${_whole.format(abs)}';
  }

  /// Plain rupee with Indian grouping, no L/Cr suffix.
  static String rupees(num amount) => '₹${_whole.format(amount)}';
}
