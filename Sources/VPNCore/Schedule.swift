import Foundation

/// Рабочее расписание автоподключения. Вне окна VPN сам не поднимается: только вручную, из виджета или по запросу
/// пилота; после такого включения автоподключение держится ещё `afterHoursHoldMinutes` минут.
public struct WorkSchedule: Codable, Equatable {
    public var enabled = true
    /// Минуты от полуночи.
    public var startMinutes = 9 * 60
    public var endMinutes = 18 * 60
    /// Номера дней по `Calendar` (1 — воскресенье, 2 — понедельник…).
    public var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    public var afterHoursHoldMinutes = 180
    public init() {}

    enum CodingKeys: String, CodingKey { case enabled, startMinutes, endMinutes, weekdays, afterHoursHoldMinutes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = WorkSchedule()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? base.enabled
        startMinutes = try c.decodeIfPresent(Int.self, forKey: .startMinutes) ?? base.startMinutes
        endMinutes = try c.decodeIfPresent(Int.self, forKey: .endMinutes) ?? base.endMinutes
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? base.weekdays
        afterHoursHoldMinutes = try c.decodeIfPresent(Int.self, forKey: .afterHoursHoldMinutes) ?? base.afterHoursHoldMinutes
    }

    public func validated() throws -> WorkSchedule {
        var result = self
        result.weekdays = weekdays.filter { (1...7).contains($0) }
        guard (0..<1440).contains(startMinutes), (1...1440).contains(endMinutes), startMinutes < endMinutes else {
            throw KeeperError("Начало рабочего дня должно быть раньше конца.")
        }
        guard !result.weekdays.isEmpty else { throw KeeperError("Выберите хотя бы один рабочий день.") }
        result.afterHoursHoldMinutes = min(max(result.afterHoursHoldMinutes, 15), 24 * 60)
        return result
    }

    /// Расписание выключено — окно открыто всегда.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return true }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, weekdays.contains(weekday) else { return false }
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minutes >= startMinutes && minutes < endMinutes
    }

    /// Ближайшее начало окна после `date` (для подписи «автоподключение с …»).
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                weekdays.contains(calendar.component(.weekday, from: day)),
                let start = calendar.date(
                    bySettingHour: startMinutes / 60, minute: startMinutes % 60, second: 0, of: day),
                start > date
            else { continue }
            return start
        }
        return nil
    }

    public static func label(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
}

/// Команды, которые принимает уже запущенное приложение (из виджета, строки меню и от пилота).
public enum KeeperCommand: Equatable {
    case connect(holdMinutes: Int?)
    case disconnect

    public static let notification = Notification.Name("kz.local.VPNKeeper.command")

    public var userInfo: [String: Any] {
        switch self {
        case .connect(let hold): return ["action": "connect", "hold": hold ?? 0]
        case .disconnect: return ["action": "disconnect"]
        }
    }

    public init?(userInfo: [AnyHashable: Any]?) {
        switch userInfo?["action"] as? String {
        case "connect":
            let hold = userInfo?["hold"] as? Int ?? 0
            self = .connect(holdMinutes: hold > 0 ? hold : nil)
        case "disconnect": self = .disconnect
        default: return nil
        }
    }
}
