import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications
import ServiceManagement
import StewardCore

final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifications()
    let center = UNUserNotificationCenter.current()
    override init() { super.init(); center.delegate = self }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }; completionHandler()
    }
    func refresh(archive: Archive, enabled: Bool, sound: Bool) {
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }
        let now = Date()
        var events: [(Date, String, String)] = []
        for offset in 0..<30 {
            let day = Day.adding(offset, to: now)
            for task in archive.tasks(on: day) where task.status != "已取消" {
                if task.remind, let start = Day.moment(day, task.start) {
                    let date = start.addingTimeInterval(-Double(task.advance * 60))
                    if date > now { events.append((date, task.title, "\(task.start)–\(task.end)" + (task.advance > 0 ? " · 提前 \(task.advance) 分钟" : " · 现在开始"))) }
                }
                if task.endReminder, let date = Day.moment(day, task.end), date > now { events.append((date, task.title, "本次安排已结束，记得记录完成情况。")) }
            }
        }
        for (index, event) in events.sorted(by: { $0.0 < $1.0 }).prefix(60).enumerated() {
            let content = UNMutableNotificationContent(); content.title = event.1; content.body = event.2
            if sound { content.sound = .default }
            let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: event.0), repeats: false)
            center.add(UNNotificationRequest(identifier: "schedule-\(index)", content: content, trigger: trigger))
        }
    }
}

@MainActor final class Store: ObservableObject {
    @Published var archive = Archive()
    @Published var date = Date()
    @Published var message = ""
    @Published var notificationStatus = "尚未检查"
    @Published var readOnly = false
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "reminders"); schedule() } }
    @Published var sound: Bool { didSet { UserDefaults.standard.set(sound, forKey: "sound"); schedule() } }
    let url: URL
    var lastTick = Date()
    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TimeSteward")
        url = dir.appendingPathComponent("records.json")
        enabled = UserDefaults.standard.object(forKey: "reminders") as? Bool ?? true
        sound = UserDefaults.standard.object(forKey: "sound") as? Bool ?? true
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
                if let issue = archive.validation() { throw NSError(domain: "TimeSteward", code: 1, userInfo: [NSLocalizedDescriptionKey: issue]) }
            }
            archive.freezePast(until: Date()); persist()
        } catch { readOnly = true; message = "数据读取失败，已停止写入以保护原文件。请从备份恢复。\n\(error.localizedDescription)" }
        checkPermission(); schedule()
        if CommandLine.arguments.contains("--import-example-plan"), !readOnly, archive.rules.isEmpty, archive.days.values.allSatisfy(\.isEmpty) { installExamplePlan() }
    }
    var key: String { Day.key(date) }
    var tasks: [TaskItem] { archive.tasks(on: date) }
    var templates: [PlanTemplate] { archive.templates }
    func persist() {
        guard !readOnly else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(archive).write(to: url, options: .atomic) }
        catch { message = "保存失败：\(error.localizedDescription)" }
    }
    func schedule() { guard !readOnly else { return }; Notifications.shared.refresh(archive: archive, enabled: enabled, sound: sound) }
    func commit() { persist(); schedule() }
    func tick() {
        let now = Date()
        if now.timeIntervalSince(lastTick) > 180 {
            let count = archive.tasks(on: now).filter { task in guard let start = Day.moment(now, task.start) else { return false }; return start > lastTick && start <= now && task.remind }.count
            if count > 0 { message = "离开期间有 \(count) 项安排开始，请查看今天的时间表。" }
        }
        if Day.key(now) != Day.key(lastTick) { archive.freezePast(until: now); persist() }
        lastTick = now; schedule()
    }
    func checkPermission() {
        Notifications.shared.center.getNotificationSettings { settings in
            DispatchQueue.main.async { self.notificationStatus = settings.authorizationStatus == .authorized ? "已允许" : settings.authorizationStatus == .notDetermined ? "尚未授权" : "未允许，请在系统设置中开启" }
        }
    }
    func requestPermission() {
        Notifications.shared.center.requestAuthorization(options: [.alert,.sound]) { _, error in
            DispatchQueue.main.async { if let error { self.message = error.localizedDescription }; self.checkPermission(); self.schedule() }
        }
    }
    func testNotification() {
        Notifications.shared.center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { DispatchQueue.main.async { self.message = "请先开启系统通知权限。" }; return }
            let content = UNMutableNotificationContent(); content.title = "时间安排管家"; content.body = "测试提醒：你的时间，由你安排。"; content.sound = .default
            Notifications.shared.center.add(UNNotificationRequest(identifier: "test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))) { error in
                DispatchQueue.main.async { self.message = error?.localizedDescription ?? "测试通知将在 5 秒后发送。" }
            }
        }
    }
    func put(_ task: TaskItem) {
        guard !readOnly else { return }
        var items = tasks
        if let i = items.firstIndex(where: { $0.id == task.id }) { items[i] = task } else { items.append(task) }
        archive.days[key] = items; commit()
    }
    func record(_ task: TaskItem, status: String) { var t = task; t.status = status; put(t) }
    func cancel(_ task: TaskItem, future: Bool) {
        guard !readOnly else { return }
        if future, let id = task.ruleID, let i = archive.rules.firstIndex(where: { $0.id == id }) {
            archive.freezePast(until: Day.adding(-1, to: date))
            archive.rules[i].through = Day.key(Day.adding(-1, to: date))
            for k in Array(archive.days.keys) where k >= key { archive.days[k] = archive.days[k]?.map { var t = $0; if t.ruleID == id { t.status = "已取消" }; return t } }
        }
        var t = task; t.status = "已取消"; put(t)
    }
    func saveTask(_ task: TaskItem, repeating: Bool, weekdays: [Int], rotation: [String], future: Bool) -> Bool {
        guard !readOnly else { return false }
        guard task.valid else { message = "请输入有效任务名称和 HH:mm 起止时间。"; return false }
        if !repeating || !future && task.ruleID != nil {
            guard !tasks.contains(where: { task.overlaps($0) }) else { message = "与当天已有安排重叠。"; return false }; put(task); return true
        }
        var base = task; base.ruleID = nil; base.status = "未记录"; base.note = ""
        let rule = Rule(task: base, from: key, weekdays: weekdays, rotation: rotation)
        // Weekly rules have a 7-day period: validate all recurring intersections, including future rule boundaries.
        var probes = Set((0..<7).map { Day.key(Day.adding($0, to: date)) })
        for old in archive.rules where old.id != task.ruleID && (old.through == nil || old.through! >= key) {
            if let boundary = Day.date(max(old.from, key)) { for n in 0..<7 { probes.insert(Day.key(Day.adding(n, to: boundary))) } }
        }
        for k in archive.days.keys where k >= key { probes.insert(k) }
        for k in probes {
            guard let d = Day.date(k), let occurrence = rule.occurrence(on: d) else { continue }
            let generated = archive.rules.filter { $0.id != task.ruleID }.compactMap { $0.occurrence(on: d) }
            let actual = archive.tasks(on: d).filter { $0.id != task.id && (task.ruleID == nil || $0.ruleID != task.ruleID) }
            if (generated + actual).contains(where: { occurrence.overlaps($0) }) { message = "重复安排在 \(k) 与其他任务重叠。请调整时间或星期。"; return false }
        }
        archive.freezePast(until: Day.adding(-1, to: date))
        if let id = task.ruleID, let i = archive.rules.firstIndex(where: { $0.id == id }) { archive.rules[i].through = Day.key(Day.adding(-1, to: date)) }
        archive.rules.append(rule)
        for k in Array(archive.days.keys) where k >= key {
            archive.days[k]?.removeAll { $0.id == task.id || (task.ruleID != nil && $0.ruleID == task.ruleID) }
            if let d = Day.date(k), var t = rule.occurrence(on: d) {
                if k == key { t.status = task.status; t.note = task.note }
                archive.days[k]?.append(t)
            }
        }
        commit(); return true
    }
    func saveTemplate(name: String) {
        guard !readOnly else { return }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !tasks.isEmpty else { message = "请先添加安排并填写模板名称。"; return }
        let items = tasks.filter { $0.status != "已取消" }.map { item -> TaskItem in var t = item; t.id = UUID().uuidString; t.ruleID = nil; t.status = "未记录"; t.note = ""; return t }
        archive.templates.append(PlanTemplate(name: cleaned, tasks: items)); persist(); message = "已保存模板「\(cleaned)」。"
    }
    func deleteTemplate(_ id: String) { guard !readOnly else { return }; archive.templates.removeAll { $0.id == id }; persist() }
    func apply(_ template: PlanTemplate, through end: Date) {
        guard !readOnly else { return }
        let count = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: end)).day ?? -1
        guard (0...366).contains(count) else { message = "请选择 0–366 天内的结束日期。"; return }
        for n in 0...count where !archive.tasks(on: Day.adding(n, to: date)).isEmpty { message = "\(Day.key(Day.adding(n, to: date))) 已有安排。为保护记录，本次未应用；请改选空白日期。"; return }
        for n in 0...count { archive.days[Day.key(Day.adding(n, to: date))] = template.tasks.map { var t = $0; t.id = UUID().uuidString; t.ruleID = nil; t.status = "未记录"; t.note = ""; return t } }
        commit(); message = "模板已应用至 \(count + 1) 天。"
    }
    func installExamplePlan() {
        guard !readOnly else { return }
        guard archive.rules.isEmpty, archive.days.values.allSatisfy(\.isEmpty) else { message = "当前已有安排，请使用模板功能选择空白日期，避免覆盖记录。"; return }
        for task in ExamplePlan.tasks { archive.rules.append(Rule(task: task, from: key, rotation: task.category == "项目" ? ExamplePlan.directions : [])) }
        archive.templates.append(PlanTemplate(name: "示例日常计划", tasks: ExamplePlan.tasks)); archive.freezePast(until: Date()); commit()
        message = "已录入示例计划，起始日为 \(key)，项目方向按四天轮换。所有任务均为未记录。"
    }
    func insertBreaks(minutes: Int) {
        guard !readOnly else { return }
        var items = tasks.filter { $0.status != "已取消" }
        guard items.count > 1 else { message = "至少需要两项任务。"; return }
        var additions: [TaskItem] = []
        for pair in zip(items, items.dropFirst()) where pair.0.category != "休息" && pair.1.category != "休息" {
            guard let end = Day.minutes(pair.0.end), let start = Day.minutes(pair.1.start), start - end >= minutes else { message = "任务间空隙不足 \(minutes) 分钟。本次未修改；请先调整时间。"; return }
            var t = TaskItem(title: "休息", start: pair.0.end, end: String(format: "%02d:%02d", (end + minutes)/60, (end + minutes)%60)); t.category = "休息"; t.counts = false; t.remind = false; additions.append(t)
        }
        items += additions; archive.days[key] = items; commit(); message = "已在当天插入 \(additions.count) 段休息，原有任务时间保持不变。"
    }
    func exportBackup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "时间安排管家备份-\(Day.key(Date())).json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted,.sortedKeys]; try e.encode(archive).write(to: target, options: .atomic); message = "备份已导出。" } catch { message = error.localizedDescription }
    }
    func restoreBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            var restored = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: source))
            if let issue = restored.validation() { throw NSError(domain: "Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: issue]) }
            let alert = NSAlert(); alert.messageText = "恢复备份并替换当前数据？"; alert.informativeText = "当前文件会先保存为恢复前备份。恢复后将使用所选文件中的计划和记录。"; alert.addButton(withTitle: "恢复"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.copyItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("before-restore-\(UUID().uuidString).json")) }
            restored.freezePast(until: Date()); archive = restored; readOnly = false; commit(); message = "备份已恢复。"
        } catch { message = "无法恢复：\(error.localizedDescription)" }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { message = "无法修改登录启动：\(error.localizedDescription)" }
        objectWillChange.send()
    }
}
