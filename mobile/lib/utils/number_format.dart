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
