#if OMARCHY
    public let stableAeroSpaceAppId: String = "com.hancengiz.macarchy"
#else
    public let stableAeroSpaceAppId: String = "bobko.aerospace"
#endif
#if DEBUG
    #if OMARCHY
        public let aeroSpaceAppId: String = "com.hancengiz.macarchy.debug"
        public let aeroSpaceAppName: String = "macarchy-Debug"
    #else
        public let aeroSpaceAppId: String = "bobko.aerospace.debug"
        public let aeroSpaceAppName: String = "AeroSpace-Debug"
    #endif
#else
    public let aeroSpaceAppId: String = stableAeroSpaceAppId
    #if OMARCHY
        public let aeroSpaceAppName: String = "macarchy"
    #else
        public let aeroSpaceAppName: String = "AeroSpace"
    #endif
#endif
