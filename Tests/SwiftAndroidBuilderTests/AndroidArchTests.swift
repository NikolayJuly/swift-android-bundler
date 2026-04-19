// AndroidArchTests.swift

import SharedStructs
import Testing

@Suite("AndroidArch")
struct AndroidArchTests {

    @Test("User-friendly name lookup and ABI names")
    func nameLookupsAndABI() {
        // CLI name lookup
        #expect(AndroidArch.fromUserFriendlyName("arm64") == .arm64)
        #expect(AndroidArch.fromUserFriendlyName("arm7") == .arm7)
        #expect(AndroidArch.fromUserFriendlyName("x86") == .x86)
        #expect(AndroidArch.fromUserFriendlyName("x86_64") == .x86_64)
        #expect(AndroidArch.fromUserFriendlyName("mips") == nil)

        // ABI names for Android folder naming
        #expect(AndroidArch.arm64.ndkABI == "arm64-v8a")
        #expect(AndroidArch.arm7.ndkABI == "armeabi-v7a")
    }
}
