import Foundation
import Testing

@testable import VPNCore

struct ScheduleTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Almaty")!
        return c
    }
    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Almaty")!
        return f.date(from: s)!
    }

    @Test func testDefaultsAreNineToSixOnWeekdays() {
        let s = WorkSchedule()
        checkTrue(s.contains(date("2026-11-13T09:00:00+05:00"), calendar: calendar))   // пятница
        checkTrue(s.contains(date("2026-11-13T17:59:00+05:00"), calendar: calendar))
        checkFalse(s.contains(date("2026-11-13T18:00:00+05:00"), calendar: calendar))
        checkFalse(s.contains(date("2026-11-13T08:59:00+05:00"), calendar: calendar))
        checkFalse(s.contains(date("2026-11-14T12:00:00+05:00"), calendar: calendar))  // суббота
    }

    @Test func testDisabledScheduleIsAlwaysOpen() {
        var s = WorkSchedule()
        s.enabled = false
        checkTrue(s.contains(date("2026-11-14T03:00:00+05:00"), calendar: calendar))
        checkNil(s.nextStart(after: Date(), calendar: calendar))
    }

    @Test func testNextStartSkipsWeekend() {
        let s = WorkSchedule()
        let next = s.nextStart(after: date("2026-11-13T19:00:00+05:00"), calendar: calendar)
        checkEqual(next, date("2026-11-16T09:00:00+05:00"))
        checkEqual(s.nextStart(after: date("2026-11-13T07:00:00+05:00"), calendar: calendar), date("2026-11-13T09:00:00+05:00"))
    }

    @Test func testValidationAndCodableDefaults() throws {
        var s = WorkSchedule()
        s.startMinutes = 19 * 60
        checkThrows(try s.validated())
        s = WorkSchedule()
        s.weekdays = []
        checkThrows(try s.validated())
        s = WorkSchedule()
        s.afterHoursHoldMinutes = 1
        checkEqual(try s.validated().afterHoursHoldMinutes, 15)
        let decoded = try JSONDecoder().decode(WorkSchedule.self, from: Data("{}".utf8))
        checkEqual(decoded, WorkSchedule())
    }

    @Test func testCommandRoundTrip() {
        for command in [KeeperCommand.connect(holdMinutes: 90), .connect(holdMinutes: nil), .disconnect] {
            checkEqual(KeeperCommand(userInfo: command.userInfo), command)
        }
        checkNil(KeeperCommand(userInfo: ["action": "format"]))
    }
}
