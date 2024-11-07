import 'models/app_model.dart';

String getRoundedTimeString(DateTime dateTime) {
  int minutes = dateTime.minute;
  int roundedMinutes = (minutes ~/ 5) * 5;
  return DateTime(dateTime.year, dateTime.month, dateTime.day, dateTime.hour,
      roundedMinutes)
      .toIso8601String()
      .substring(11, 16)
      .split(':')
      .join();
}

String getAppModelTimeText(List<AppModel> data, int index) {
  var startTime = data[index].time;
  var endTime = data[index - 1].time;

  if (index < data.length - 1) {
    // if the time difference between this event and previous event  time is less than 5 minutes
    Duration duration = startTime.difference(data[index + 1].time);
    if (duration.inMinutes < 5) {
      // add five minutes to this event start time
      startTime = data[index].time.add(const Duration(minutes: 5));
    }
  }

  var startTimeText = getRoundedTimeString(startTime);
  var endTimeText = getRoundedTimeString(endTime);

  return '$startTimeText$endTimeText';
}

