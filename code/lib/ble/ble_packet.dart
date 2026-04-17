class BlePacket {
  final double distanceMm;
  final int batteryPercent;
  final bool isCapturing;

  const BlePacket({
    required this.distanceMm,
    required this.batteryPercent,
    required this.isCapturing,
  });

  factory BlePacket.fromBytes(List<int> bytes) {
    if (bytes.length < 4) {
      return const BlePacket(
        distanceMm: 0,
        batteryPercent: 0,
        isCapturing: false,
      );
    }
    final int dist = (bytes[0] << 8) | bytes[1];
    return BlePacket(
      distanceMm: dist.toDouble(),
      batteryPercent: bytes[2],
      isCapturing: (bytes[3] & 0x01) != 0,
    );
  }
}