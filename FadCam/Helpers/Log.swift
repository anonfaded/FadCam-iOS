import OSLog

enum FadCamLog {
    private static let subsystem = "com.fadseclab.fadcam"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let recorder = Logger(subsystem: subsystem, category: "recorder")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let trash = Logger(subsystem: subsystem, category: "trash")
    static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
}
