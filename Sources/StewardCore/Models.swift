import Foundation

public enum Day {
    public static func key(_ date: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    public static func date(_ key: String) -> Date? { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false; return f.date(from: key) }
    public static func adding(_ n: Int, to date: Date) -> Date { Calendar.current.date(byAdding: .day, value: n, to: date)! }
    public static func minutes(_ s: String) -> Int? {
        guard s.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil else { return nil }
        let p = s.split(separator: ":").compactMap { Int($0) }; return p[0] * 60 + p[1]
    }
    public static func moment(_ date: Date, _ time: String) -> Date? { guard let m = minutes(time) else { return nil }; return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: date) }
}
public struct TaskItem: Identifiable, Codable, Equatable {
    public var id: String = UUID().uuidString
    public var ruleID: String? = nil
    public var title: String
    public var start: String
    public var end: String
    public var category = "学习"
    public var counts = true
    public var status = "未记录"
    public var note = ""
    public var detail = ""
    public var remind = true
    public var endReminder = false
    public var advance = 0
    public init(title: String = "", start: String = "09:00", end: String = "10:00") { self.title = title; self.start = start; self.end = end }
    enum CodingKeys: String, CodingKey { case id, ruleID, title, start, end, category, counts, status, note, detail, remind, endReminder, advance }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); ruleID = try c.decodeIfPresent(String.self, forKey: .ruleID)
        title = try c.decode(String.self, forKey: .title); start = try c.decode(String.self, forKey: .start); end = try c.decode(String.self, forKey: .end)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "学习"; counts = try c.decodeIfPresent(Bool.self, forKey: .counts) ?? true
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "未记录"; note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""; remind = try c.decodeIfPresent(Bool.self, forKey: .remind) ?? true
        endReminder = try c.decodeIfPresent(Bool.self, forKey: .endReminder) ?? false; advance = try c.decodeIfPresent(Int.self, forKey: .advance) ?? 0
    }
    public var duration: Int { max(0, (Day.minutes(end) ?? 0) - (Day.minutes(start) ?? 0)) }
    public var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Day.minutes(start) != nil && Day.minutes(end) != nil && start < end && (0...120).contains(advance) }
    public func overlaps(_ other: TaskItem) -> Bool { id != other.id && status != "已取消" && other.status != "已取消" && start < other.end && other.start < end }
}
public struct Rule: Identifiable, Codable {
    public var id = UUID().uuidString
    public var task: TaskItem
    public var from: String
    public var through: String? = nil
    public var weekdays: [Int] = [] // Calendar weekdays; empty means every day
    public var rotation: [String] = []
    public init(task: TaskItem, from: String, weekdays: [Int] = [], rotation: [String] = []) { self.task = task; self.from = from; self.weekdays = weekdays; self.rotation = rotation }
    public func occurrence(on date: Date) -> TaskItem? {
        let key = Day.key(date), calendar = Calendar.current
        guard key >= from, through == nil || key <= through!, weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: date)) else { return nil }
        var t = task; t.id = id + "/" + key; t.ruleID = id; t.status = "未记录"; t.note = ""
        if !rotation.isEmpty, let anchor = Day.date(from) {
            let span = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day ?? 0
            let fullWeeks = span / 7
            var index = weekdays.isEmpty ? span : fullWeeks * weekdays.count
            if !weekdays.isEmpty { for n in (fullWeeks * 7)..<span { if weekdays.contains(calendar.component(.weekday, from: Day.adding(n, to: anchor))) { index += 1 } } }
            t.title = task.title + " · " + rotation[index % rotation.count]
        }
        return t
    }
}
public struct PlanTemplate: Identifiable, Codable {
    public var id = UUID().uuidString
    public var name: String
    public var tasks: [TaskItem]
    public init(name: String, tasks: [TaskItem]) { self.name = name; self.tasks = tasks }
}
public struct Archive: Codable {
    public var version = 2
    public var days: [String: [TaskItem]] = [:]
    public var rules: [Rule] = []
    public var templates: [PlanTemplate] = []
    public init() {}
    enum CodingKeys: String, CodingKey { case version, days, rules, templates }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version <= 2 else { throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "备份版本高于当前软件") }
        days = try c.decode([String: [TaskItem]].self, forKey: .days)
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        templates = try c.decodeIfPresent([PlanTemplate].self, forKey: .templates) ?? []
    }
    public func tasks(on date: Date) -> [TaskItem] { (days[Day.key(date)] ?? rules.compactMap { $0.occurrence(on: date) }).sorted { $0.start < $1.start } }
    public mutating func freezePast(until date: Date) {
        guard let first = rules.map(\.from).min().flatMap(Day.date) else { return }
        var d = first
        while d <= Calendar.current.startOfDay(for: date) {
            let k = Day.key(d)
            if days[k] == nil { days[k] = tasks(on: d) }
            d = Day.adding(1, to: d)
        }
    }
    public func validation() -> String? {
        let all = Array(days.values).flatMap { $0 } + rules.map(\.task) + templates.flatMap(\.tasks)
        guard all.allSatisfy(\.valid) else { return "包含无效的任务名称、时间或提醒设置" }
        guard days.keys.allSatisfy({ Day.date($0) != nil }), rules.allSatisfy({ Day.date($0.from) != nil && ($0.through == nil || Day.date($0.through!) != nil) && $0.weekdays.allSatisfy { (1...7).contains($0) } }) else { return "日期或重复规则无效" }
        guard Set(rules.map(\.id)).count == rules.count, days.values.allSatisfy({ Set($0.map(\.id)).count == $0.count }) else { return "存在重复的任务标识" }
        return nil
    }
}
public struct Summary {
    public var total = 0, completed = 0, partial = 0, missed = 0, unrecorded = 0, minutes = 0
    public var categories: [String: Int] = [:]
    public init(tasks: [TaskItem]) {
        for t in tasks where t.counts && t.status != "已取消" {
            total += 1; minutes += t.duration; categories[t.category, default: 0] += 1
            switch t.status { case "已完成": completed += 1; case "部分完成": partial += 1; case "未完成": missed += 1; default: unrecorded += 1 }
        }
    }
    public var rate: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}
public enum ExamplePlan {
    public static let directions = ["写作实验", "设计练习", "小工具开发", "产品验证"]
    public static var tasks: [TaskItem] {
        let rows = [("08:30","09:15","工作规划","工作"),("09:15","09:30","休息","休息"),("09:30","11:00","技术学习","学习"),("11:00","11:15","休息","休息"),("11:15","12:00","阅读练习","学习"),("12:00","14:00","午饭与午休","休息"),("14:00","16:00","项目实践","项目"),("16:00","16:15","休息","休息"),("16:15","17:15","专业学习","学习"),("17:15","17:30","休息","休息"),("17:30","18:30","运动","运动"),("18:30","20:00","洗澡、晚饭与休息","休息"),("20:00","22:00","兴趣练习","兴趣"),("22:00","22:15","休息","休息"),("22:15","23:15","学习复盘","学习"),("23:15","23:30","洗漱、准备睡觉","休息")]
        return rows.map { row in
            var t = TaskItem(title: row.2, start: row.0, end: row.1); t.category = row.3; t.counts = row.3 != "休息"; t.remind = t.counts
            if row.2 == "兴趣练习" { t.detail = "20:00–20:30 热身\n20:30–21:00 回顾\n21:00–22:00 学习新内容" }
            if row.2 == "阅读练习" { t.detail = "阅读感兴趣的内容并记录要点。" }
            if row.2 == "工作规划" { t.detail = "整理当日工作目标与待办事项。" }
            return t
        }
    }
}
