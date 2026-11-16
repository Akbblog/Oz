import 'package:flutter/foundation.dart';

/// App-wide "data changed" signals.
///
/// Home tabs are kept alive (IndexedStack) so they no longer rebuild - and
/// therefore no longer reload - on every visit. Screens listen here instead:
/// [tabActivated] fires when the user switches to a tab (value = page index),
/// [jobsChanged] fires when a job is created or reaches a final state.
class RefreshBus {
  RefreshBus._();

  static final ValueNotifier<int> tabActivated = ValueNotifier<int>(-1);
  static final ValueNotifier<int> jobsChanged = ValueNotifier<int>(0);

  static void activateTab(int index) {
    // Re-assigning the same index must still notify.
    if (tabActivated.value == index) {
      tabActivated.value = -1;
    }
    tabActivated.value = index;
  }

  static void notifyJobsChanged() => jobsChanged.value++;
}
