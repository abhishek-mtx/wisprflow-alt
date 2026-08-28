import Foundation

@MainActor
final class StatsStore {
    static let shared = StatsStore()

    private let defaults = UserDefaults.standard
    private let wordsKey = "stats.totalWords"
    private let dayKey = "stats.day"
    private let streakKey = "stats.streak"
    private let lastActiveKey = "stats.lastActiveDay"

    private init() {}

    var totalWords: Int { defaults.integer(forKey: wordsKey) }
    var streak: Int { defaults.integer(forKey: streakKey) }

    func record(words: Int, at date: Date) {
        defaults.set(totalWords + words, forKey: wordsKey)

        let day = Self.dayString(date)
        let last = defaults.string(forKey: lastActiveKey)
        if last != day {
            if let last,
               let lastDate = Self.date(from: last),
               Calendar.current.dateComponents([.day], from: lastDate, to: date).day == 1
            {
                defaults.set(streak + 1, forKey: streakKey)
            } else if last == nil {
                defaults.set(1, forKey: streakKey)
            } else {
                defaults.set(1, forKey: streakKey)
            }
            defaults.set(day, forKey: lastActiveKey)
        }

        var dayWords = defaults.dictionary(forKey: dayKey) as? [String: Int] ?? [:]
        dayWords[day, default: 0] += words
        defaults.set(dayWords, forKey: dayKey)
    }

    var todayWords: Int {
        let day = Self.dayString(Date())
        let dayWords = defaults.dictionary(forKey: dayKey) as? [String: Int] ?? [:]
        return dayWords[day, default: 0]
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func date(from day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }
}
