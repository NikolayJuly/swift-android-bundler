// BuildOptions.swift

public enum StripMode: String, CaseIterable, Sendable {
    case none
    case debug
    case all
}

public enum BuildConfiguration: String, CaseIterable, Sendable {
    case debug
    case release
}

public enum ExcludeMode: String, CaseIterable, Sendable {
    case none
    case fullFoundation = "full-foundation"
    case foundationNetworking = "foundation-networking"
    case all
}
