import Testing

@testable import TaskCore

struct PowerModeTests {
  @Test func unifiedProfilesPreserveHighPower() {
    let result = MacPowerConfiguration.parse(
      "Battery Power:\n powermode 0\nAC Power:\n powermode 2\n")
    #expect(result[.battery]?.mode == .automatic)
    #expect(result[.ac]?.mode == .high)
    #expect(result[.ac]?.usesUnifiedKey == true)
  }
  @Test func legacyMacsUseLowPowerKey() {
    let result = MacPowerConfiguration.parse(
      "Battery Power:\n lowpowermode 1\nAC Power:\n lowpowermode 0\n")
    #expect(result[.battery]?.mode == .low)
    #expect(result[.ac]?.usesUnifiedKey == false)
  }
  @Test func unrelatedOrMalformedValuesAreRejected() {
    let result = MacPowerConfiguration.parse(
      "AC Power:\n sleep 1\n powermode 99\n lowpowermode bogus\nUPS Power:\n powermode 1\n")
    #expect(result.isEmpty)
  }
  @Test func powerWritesStayScopedAndRestoreHighMode() {
    let profile = MacPowerProfile(mode: .high, usesUnifiedKey: true)
    #expect(profile.command(source: .ac, target: .low) == "/usr/bin/pmset -c powermode 1")
    #expect(profile.command(source: .ac, target: .high) == "/usr/bin/pmset -c powermode 2")
    #expect(
      profile.command(source: .battery, target: .automatic) == "/usr/bin/pmset -b powermode 0")
  }
  @Test func legacyProfilesCannotReceiveHighPowerMode() {
    let profile = MacPowerProfile(mode: .automatic, usesUnifiedKey: false)
    #expect(profile.command(source: .battery, target: .low) == "/usr/bin/pmset -b lowpowermode 1")
    #expect(profile.command(source: .ac, target: .high) == nil)
  }
}
