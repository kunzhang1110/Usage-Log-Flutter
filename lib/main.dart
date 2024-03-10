import 'constants.dart';
import 'models/app_event.dart';
import 'models/app_model.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:usage_stats/usage_stats.dart';
import 'package:android_package_manager/android_package_manager.dart';

import 'models/app_usage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<AppEvent> _appEvents = [];
  List<AppUsage> _appUsages = [];
  int _selectedIndex = 1;
  final AndroidPackageManager _packageManager = AndroidPackageManager();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshIndicatorKey.currentState
          ?.show(); //calling the _getAppData() in onRefresh
    });
  }

  bool _isResumedOrNonInteractive(AppEvent appEvent) {
    return appEvent.eventType == "Activity Resumed" ||
        appEvent.eventType == "Screen Non-Interactive";
  }

  Future<void> _getAppData() async {
    UsageStats.grantUsagePermission();

    if (_appEvents.isNotEmpty) {
      setState(() {
        _appEvents = [];
        _appUsages = [];
      });
    }

    DateTime endDate = DateTime.now();
    DateTime startDate =
        endDate.add(const Duration(days: -daysOfEventsIncluded));

    List<EventUsageInfo> queryEvents =
        await UsageStats.queryEvents(startDate, endDate);

    List<AppEvent> appEvents = [];
    List<AppUsage> appUsages = [];
    Map<String, List<AppEvent>> appNameToAppEventMap = {};

    for (var event in queryEvents) {
      var packageName = event.packageName;
      var eventType = eventTypeMap[int.parse(event.eventType!)];
      if (eventType == null || packageName == null) continue;

      var appEvent = AppEvent(
        appName: await _packageManager.getApplicationLabel(
                packageName: packageName) ??
            packageName,
        appIconByte:
            await _packageManager.getApplicationIcon(packageName: packageName),
        eventType: eventType,
        time: DateTime.fromMillisecondsSinceEpoch(int.parse(event.timeStamp!)),
      );

      if (eventTypeForDurationList.contains(eventType)) {
        appNameToAppEventMap
            .putIfAbsent(appEvent.appName, () => List.empty(growable: true))
            .add(appEvent);
      }
      appEvents.add(appEvent);
    }

    appNameToAppEventMap.forEach(
      (String appName, List<AppEvent> list) {
        for (int x = 0; x < list.length; x++) {
          var eventX = list[x];

          if (_isResumedOrNonInteractive(eventX)) {
            int y = x + 1;

            while (y < list.length && _isResumedOrNonInteractive(list[y])) {
              y++;
            }

            if (y < list.length) {
              var eventY = list[y];
              Duration duration = eventY.time.difference(eventX.time);
              int durationInSeconds = duration.inSeconds;

              if (durationInSeconds > 0) {
                var appUsage = AppUsage(
                  appName:
                      appName == "Android System" ? "Screen Locked" : appName,
                  appIconByte: eventX.appIconByte,
                  time: eventX.time,
                  durationInSeconds: durationInSeconds,
                );
                appUsage.durationInSeconds = durationInSeconds;
                appUsages.add(appUsage);
                x = y;
              }
            }
          }
        }
      },
    );

    setState(() {
      _appEvents = appEvents.reversed.toList();
      _appUsages = (appUsages..sort()).reversed.toList();
    });
  }

  String _getRoundedTimeString(DateTime dateTime) {
    int minutes = dateTime.minute;
    int roundedMinutes = (minutes / 5).round() * 5;
    return DateTime(dateTime.year, dateTime.month, dateTime.day, dateTime.hour,
            roundedMinutes)
        .toIso8601String()
        .substring(11, 16)
        .split(':')
        .join();
  }

  String _handleLongPress(
      List<AppModel> appModels, int index, BuildContext context) {
    var startTime = _getRoundedTimeString(appModels[index].time);
    var endTime = _getRoundedTimeString(appModels[index - 1].time);

    var result = '$startTime$endTime';

    return result;
  }

  Widget _buildListView() {
    List<AppModel> appModels = [];

    if (_selectedIndex == 0) {
      //only show each Screen Locked that is longer than 10 mins. and the activity before it
      for (int i = 1; i < _appUsages.length; i++) {
        if (_appUsages[i].appName == "Screen Locked" &&
            (_appUsages[i].durationInSeconds >= 600)) {
          appModels.add(_appUsages[i - 1]);
          appModels.add(_appUsages[i]);
        }
      }
    }

    if (_selectedIndex == 1) {
      appModels = _appUsages;
    }

    if (_selectedIndex == 2) {
      appModels = _appEvents;
    }

    return ListView.separated(
        controller: _controller,
        separatorBuilder: (context, index) => const Divider(),
        itemCount: appModels.length,
        itemBuilder: (context, index) {
          return InkWell(
            onLongPress: () async {
              if (index >= 1 && _selectedIndex == 0) {
                await Clipboard.setData(ClipboardData(
                    text: _handleLongPress(appModels, index, context)));
              }
            },
            child: Padding(
              padding: _selectedIndex == 2
                  ? const EdgeInsets.fromLTRB(45, 5, 0, 5)
                  : const EdgeInsets.symmetric(horizontal: 45, vertical: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text(appModels[index].time.toString().substring(0, 16)),
                  const SizedBox(
                    width: 25,
                  ),
                  appModels[index].appIconByte != null
                      ? Image.memory(
                          appModels[index].appIconByte!,
                          width: 35,
                          height: 35,
                        )
                      : const Text(""),
                  const SizedBox(
                    width: 25,
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        Widget? subText;
                        if (_selectedIndex == 0 || _selectedIndex == 1) {
                          var appUsage = appModels[index] as AppUsage;
                          subText = Text(
                            "${appUsage.durationInText}",
                            style: TextStyle(
                                color: appUsage.durationInSeconds >
                                        conciseMinTimeInSeconds //if duration longer than 30 minutes make font red
                                    ? Colors.red
                                    : Colors.black),
                          );
                        }
                        if (_selectedIndex == 2) {
                          var appEvent = appModels[index] as AppEvent;
                          subText = Text(
                            "${appEvent.eventType}",
                            overflow: TextOverflow.visible,
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(appModels[index].appName),
                            if (subText != null) subText
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    var content = _buildListView();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Usage Log"),
        ),
        body: RefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: _getAppData,
          child: Center(
            child: content,
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            _controller.animateTo(
              0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
          },
          mini: true,
          child: const Icon(
            Icons.arrow_upward,
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.summarize),
              label: 'Concise',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.topic),
              label: 'All',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.stacked_bar_chart),
              label: 'Raw',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.amber[800],
          onTap: (int index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
      ),
    );
  }
}
