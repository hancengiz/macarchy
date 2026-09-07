#if OMARCHY
    public let stableAeroSpaceAppId: String = "com.hancengiz.aerospace"
#else
    public let stableAeroSpaceAppId: String = "bobko.aerospace"
#endif
#if DEBUG
    public let aeroSpaceAppId: String = "bobko.aerospace.debug"
    public let aeroSpaceAppName: String = "AeroSpace-Debug"
#else
    public let aeroSpaceAppId: String = stableAeroSpaceAppId
    #if OMARCHY
        public let aeroSpaceAppName: String = "AeroSpace Omarchy"
    #else
        public let aeroSpaceAppName: String = "AeroSpace"
    #endif
#endif
