import 'package:flutter/services.dart';

// Inserts comma thousands separators into a non-negative integer string,
// e.g. "1234567" -> "1,234,567". Shared by every amount display across the
// app and by the live-formatting amount input field.
String addThousandsSeparators(String digits) {
  if (digits.length <= 3) return digits;
  final offset = digits.length % 3;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (i - offset) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

// Parses an amount a user may have typed or pasted with thousands
// separators (e.g. "1,000,000") — double.tryParse on its own chokes on the
// commas. Used by every amount field's submit/validate path.
double? parseAmount(String v) => double.tryParse(v.trim().replaceAll(',', ''));

// Formats an amount for an editable text field: the integer part always
// gets comma separators; the fractional part is shown with two decimals
// only when the amount actually has one (or when the caller always wants
// two, e.g. per-item amounts) — never truncated away, so an amount like
// 15.75 isn't rounded to 16 just because it's being displayed for editing.
String formatAmountForInput(double amount, {bool alwaysShowDecimals = false}) {
  if (amount == 0 && !alwaysShowDecimals) return '';
  final isWhole = amount == amount.roundToDouble();
  final raw = (!alwaysShowDecimals && isWhole) ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  final dotIndex = raw.indexOf('.');
  if (dotIndex == -1) return addThousandsSeparators(raw);
  return '${addThousandsSeparators(raw.substring(0, dotIndex))}${raw.substring(dotIndex)}';
}

// Auto-inserts thousands separators as digits are typed (e.g. typing
// "1000000" on the numeric keypad shows "1,000,000") so entering a large
// amount with commas doesn't depend on the keypad having a comma key.
// parseAmount strips them back out before the value is used. Shared by
// every amount input field in the app.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final digitsAndDot = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final dotIndex = digitsAndDot.indexOf('.');
    final intPart = dotIndex == -1 ? digitsAndDot : digitsAndDot.substring(0, dotIndex);
    final decPart =
        dotIndex == -1 ? null : digitsAndDot.substring(dotIndex + 1).replaceAll('.', '');

    final formatted = decPart == null
        ? addThousandsSeparators(intPart)
        : '${addThousandsSeparators(intPart)}.$decPart';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
