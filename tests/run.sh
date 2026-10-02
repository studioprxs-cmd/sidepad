#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
pd_java="${JAVA_HOME:-$(/usr/libexec/java_home -v 17)}"
mkdir -p build/tests
"$pd_java/bin/javac" -d build/tests android/src/studio/prxs/paddisplay/TouchGesture.java tests/TouchGestureTest.java
"$pd_java/bin/java" -cp build/tests studio.prxs.paddisplay.TouchGestureTest
for pd_name in pen touch audio layout foreground update; do
  clang -fobjc-arc -fmodules -O2 "mac/test-$pd_name.m" -o "build/tests/test-$pd_name" -framework Cocoa -framework ApplicationServices
  "build/tests/test-$pd_name"
done
