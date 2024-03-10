import 'dart:typed_data';

class AppModel implements Comparable<AppModel> {
  AppModel({
    required this.appName,
    required this.appIconByte,
    required this.time,
  });

  String appName;
  Uint8List? appIconByte;
  DateTime time;

  @override
  int compareTo(AppModel other) {
    return time.compareTo(other.time);
  }
}
