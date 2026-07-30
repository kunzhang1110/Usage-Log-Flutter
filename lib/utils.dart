import 'models/app_model.dart';

String roundedTimeString(DateTime dateTime) {
  int minutes = dateTime.minute;
  int roundedMinutes = (minutes ~/ 5) * 5;
  return DateTime(dateTime.year, dateTime.month, dateTime.day, dateTime.hour,
      roundedMinutes)
      .toIso8601String()
      .substring(11, 16)
      .split(':')
      .join();
}

String appModelTimeText(List<AppModel> data, int index) {
  var startTime = data[index].time;
  var endTime = data[index - 1].time;

  if (index < data.length - 1) {
    // Nudge start time forward when this event is within 5 minutes of the next.
    Duration duration = startTime.difference(data[index + 1].time);
    if (duration.inMinutes < 5) {
      startTime = data[index].time.add(const Duration(minutes: 5));
    }
  }

  var startTimeText = roundedTimeString(startTime);
  var endTimeText = roundedTimeString(endTime);

  return '$startTimeText$endTimeText';
}

