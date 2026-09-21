class ArgentinaDateUtils {
  static const int _utcOffsetHours = 3;

  static DateTime ahoraArgentina() {
    return DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: _utcOffsetHours));
  }

  static DateTime inicioDiaUtc(DateTime fechaArgentina) {
    return DateTime.utc(
      fechaArgentina.year,
      fechaArgentina.month,
      fechaArgentina.day,
      _utcOffsetHours,
    );
  }

  static DateTime finDiaExclusivoUtc(DateTime fechaArgentina) {
    return DateTime.utc(
      fechaArgentina.year,
      fechaArgentina.month,
      fechaArgentina.day + 1,
      _utcOffsetHours,
    );
  }
}