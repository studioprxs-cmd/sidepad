#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
pd_java="${JAVA_HOME:-$(/usr/libexec/java_home -v 17)}"
mkdir -p build/tests
"$pd_java/bin/javac" -d build/tests android/src/studio/prxs/paddisplay/TouchGesture.java android/src/studio/prxs/paddisplay/StreamStats.java android/src/studio/prxs/paddisplay/CursorPackets.java tests/TouchGestureTest.java tests/StreamStatsTest.java tests/CursorPacketsTest.java
"$pd_java/bin/java" -cp build/tests studio.prxs.paddisplay.TouchGestureTest
"$pd_java/bin/java" -cp build/tests studio.prxs.paddisplay.StreamStatsTest
"$pd_java/bin/java" -cp build/tests studio.prxs.paddisplay.CursorPacketsTest
for pd_name in pen touch audio layout foreground update updater-state receiver tuning cursor; do
  clang -fobjc-arc -fmodules -O2 "mac/test-$pd_name.m" -o "build/tests/test-$pd_name" -framework Cocoa -framework ApplicationServices
  "build/tests/test-$pd_name"
done
