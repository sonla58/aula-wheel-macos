import os

/// Stream with: /usr/bin/log stream --level debug --predicate 'subsystem == "dev.aulawheel.AulaWheel"'
enum Log {
    static let input = Logger(subsystem: "dev.aulawheel.AulaWheel", category: "input")
    static let remap = Logger(subsystem: "dev.aulawheel.AulaWheel", category: "remap")
}
