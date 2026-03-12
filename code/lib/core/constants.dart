class AppConstants {
  // BLE Service and Characteristic UUIDs
  // These must match what you define in the ESP32 firmware later
  static const String bleServiceUUID = "12345678-1234-1234-1234-123456789abc";
  static const String bleCharacteristicUUID = "abcdefab-cdef-abcd-efab-cdefabcdefab";
  static const String deviceName = "SmartMeasurePro";

  // App settings
  static const String appName = "SmartMeasure Pro";
  static const String dbName = "smart_measure.db";
}