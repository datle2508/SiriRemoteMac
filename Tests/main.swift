// main.swift (test)
// Chạy:  ./test.sh

import Foundation

runUnitTests()
runPumpTests()
runSmoothnessTests()

print("\n\(testsRun - testsFailed)/\(testsRun) test đạt" + (testsFailed > 0 ? " — \(testsFailed) LỖI" : ""))
exit(testsFailed > 0 ? 1 : 0)
