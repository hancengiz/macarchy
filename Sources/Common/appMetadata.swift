public let stableAppId: String = "com.hancengiz.macarchy"
#if DEBUG
    public let appId: String = "com.hancengiz.macarchy.debug"
    public let appName: String = "macarchy-Debug"
#else
    public let appId: String = stableAppId
    public let appName: String = "macarchy"
#endif
