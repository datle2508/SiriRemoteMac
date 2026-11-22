#!/bin/bash
# Phân tích bản ghi cảm ứng:  tools/analyze.sh touch.csv [touchspeed] [độ mượt]
# (ghi bằng: swiftc -O tools/TouchRecorder.swift -o touchrecorder && ./touchrecorder 120 touch.csv)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SRC=$(ls Sources/*.swift | grep -v '/main.swift$')
swiftc -O -target "$(uname -m)-apple-macos13" $SRC tools/TouchAnalyzer/main.swift -o build/touchanalyzer
./build/touchanalyzer "$@"
