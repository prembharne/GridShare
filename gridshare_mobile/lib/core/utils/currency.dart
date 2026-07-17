/// Invoice wording is compliance-critical: we bill "Infrastructure Facility &
/// Leasing Service Fee", NEVER "electricity". Centralized so the string is
/// consistent across mobile, web, and PDF receipts (Difficult #10).
class Compliance {
  static const String serviceLabel = 'Infrastructure Facility & Leasing Service Fee';
  static const String lineItem = 'Charging Bay Access & Leasing';
  static const String appTagline = 'GridShare — shared EV charging, peer to peer.';

  static String rupees(double v) => '${v.toInt()} credits';
}
