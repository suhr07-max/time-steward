import SwiftUI
import AppKit
import Charts
import ServiceManagement
import StewardCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static let store = Store()
    private var window: NSWindow?
    func showMainWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 850), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
            w.title = "时间安排管家"; w.minSize = NSSize(width: 1120, height: 740); w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainView(store: Self.store)); w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); showMainWindow()
        if CommandLine.arguments.contains("--request-notifications") { Self.store.requestPermission() }
        if let i = CommandLine.arguments.firstIndex(of: "--runtime-report"), CommandLine.arguments.count > i + 1 {
            let output = URL(fileURLWithPath: CommandLine.arguments[i+1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Notifications.shared.center.getNotificationSettings { settings in
                    Notifications.shared.center.getPendingNotificationRequests { requests in
                        let data: [String: Any] = ["notificationAuthorization": settings.authorizationStatus.rawValue, "pendingNotifications": requests.count, "bundleID": Bundle.main.bundleIdentifier ?? "", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""]
                        if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted,.sortedKeys]) { try? encoded.write(to: output, options: .atomic) }
                    }
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMainWindow(); return true }
}

@main struct TimeStewardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
        MenuBarExtra("时间安排管家", systemImage: "clock") {
            Button("打开时间安排管家") { delegate.showMainWindow() }
            Text("关闭窗口后仍在后台运行")
            Divider(); Button("退出") { NSApp.terminate(nil) }
        }
    }
}

struct MainView: View {
    @ObservedObject var store: Store
    @State private var page: String = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--page"), args.count > i + 1, ["今天","计划","统计","设置"].contains(args[i+1]) { return args[i+1] }
        return "今天"
    }()
    @State private var editing: TaskItem?
    @State private var now = Date()
    @State private var cancelTask: TaskItem?
    @State private var cancelFuture = false
    @State private var templateName = ""
    @State private var selectedTemplate = ""
    @State private var applyEnd = Date()
    @State private var applyConfirm = false
    @State private var personalConfirm = false
    @State private var deleteTemplate: PlanTemplate?
    @State private var breakMinutes = 15
    @State private var statsPeriod = "周"
    @State private var category = "全部"
    @State private var calendarOpen = false
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    var current: TaskItem? {
        guard Calendar.current.isDateInToday(store.date) else { return nil }
        return store.tasks.first { $0.status != "已取消" && (Day.moment(now, $0.start) ?? .distantFuture) <= now && now < (Day.moment(now, $0.end) ?? .distantPast) }
    }
    var next: TaskItem? { store.tasks.first { $0.status != "已取消" && (Day.moment(store.date, $0.start) ?? .distantPast) > now } }
    var summary: Summary { Summary(tasks: store.tasks) }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.fill").font(.system(size: 30)).foregroundStyle(.white).padding(7).background(LinearGradient(colors: [.blue.opacity(0.65),.blue], startPoint: .topLeading, endPoint: .bottomTrailing)).cornerRadius(12)
                    Text("时间安排管家").font(.system(size: 16, weight: .semibold))
                }.padding(.top, 14)
                VStack(spacing: 7) {
                    ForEach([("今天","calendar"),("计划","list.bullet.rectangle"),("统计","chart.bar.xaxis")], id: \.0) { title, icon in
                        Button { page = title } label: { Label(title, systemImage: icon).font(.system(size: 16, weight: page == title ? .semibold : .regular)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12).background(page == title ? Color.blue : .clear).foregroundStyle(page == title ? .white : .primary).cornerRadius(9) }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Button { page = "设置" } label: { Label("设置", systemImage: "gearshape").font(.system(size: 16)).padding(.vertical, 8) }.buttonStyle(.plain)
                Label(store.readOnly ? "数据保护模式" : "本地保存", systemImage: store.readOnly ? "exclamationmark.shield" : "externaldrive").foregroundStyle(.secondary).font(.caption)
            }.padding(20).background(.ultraThinMaterial).navigationSplitViewColumnWidth(min: 220, ideal: 230, max: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if page == "设置" { settings }
                    else if page == "统计" { statistics }
                    else if page == "计划" { plans }
                    else { today }
                }.padding(28)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 1120, minHeight: 740)
        .sheet(item: $editing) { Editor(store: store, task: $0) }
        .alert("时间安排管家", isPresented: Binding(get: { !store.message.isEmpty }, set: { if !$0 { store.message = "" } })) { Button("好") { store.message = "" } } message: { Text(store.message) }
        .alert("取消安排？", isPresented: Binding(get: { cancelTask != nil }, set: { if !$0 { cancelTask = nil } })) {
            Button("保留", role: .cancel) { cancelTask = nil }
            Button("确认取消", role: .destructive) { if let t = cancelTask { store.cancel(t, future: cancelFuture) }; cancelTask = nil }
        } message: { Text(cancelFuture ? "当天及以后的该重复任务将被取消，过去的记录保留。" : "取消后保留记录，不计入当天完成率。") }
        .alert("应用模板？", isPresented: $applyConfirm) { Button("取消", role: .cancel) {}; Button("应用") { if let t = store.templates.first(where: { $0.id == selectedTemplate }) { store.apply(t, through: applyEnd) } } } message: { Text("将应用到 \(Day.key(store.date)) 至 \(Day.key(applyEnd))。若范围内已有安排，将停止应用，不覆盖现有记录。") }
        .alert("录入示例计划？", isPresented: $personalConfirm) { Button("取消", role: .cancel) {}; Button("录入") { store.installExamplePlan() } } message: { Text("从所选日期开始每天安排，并启用四天轮换。已有任务时不会覆盖。") }
        .alert("删除模板？", isPresented: Binding(get: { deleteTemplate != nil }, set: { if !$0 { deleteTemplate = nil } })) { Button("取消", role: .cancel) {}; Button("删除", role: .destructive) { if let t = deleteTemplate { store.deleteTemplate(t.id) }; deleteTemplate = nil } } message: { Text("仅删除模板，不影响已应用的日期安排。") }
        .onReceive(timer) { now = $0; store.tick() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in now = Date(); store.tick(); store.checkPermission() }
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) { Text(page).font(.system(size: 32, weight: .bold)); Text(store.date.formatted(.dateTime.month(.wide).day().weekday(.wide))).foregroundStyle(.secondary) }
            Spacer()
            if page != "设置" {
                HStack(spacing: 8) {
                    Button { store.date = Day.adding(-1, to: store.date) } label: { Image(systemName: "chevron.left") }
                    Button { calendarOpen.toggle() } label: { Label(store.date.formatted(.dateTime.month().day()), systemImage: "calendar") }
                        .popover(isPresented: $calendarOpen) { DatePicker("选择日期", selection: $store.date, displayedComponents: .date).datePickerStyle(.graphical).padding(16).frame(width: 310) }
                    Button { store.date = Day.adding(1, to: store.date) } label: { Image(systemName: "chevron.right") }
                    Button("今天") { store.date = Date() }
                }.controlSize(.large)
                if page != "统计" { Button { editing = TaskItem() } label: { Label("添加任务", systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.readOnly) }
            }
        }
    }
    private var today: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 18) {
                currentCard
                if let next { HStack { Text("下一项").font(.caption).foregroundStyle(.secondary); Text(next.start).monospacedDigit(); Text(next.title); Spacer() }.padding(13).background(Color.blue.opacity(0.045)).cornerRadius(10) }
                taskList
            }.frame(maxWidth: .infinity)
            VStack(spacing: 18) { progressCard; weekCard; rotationCard }.frame(width: 250)
        }
    }
    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(current == nil ? (Calendar.current.isDateInToday(store.date) ? "自由时间" : "查看计划") : "正在进行").font(.caption.weight(.semibold)).foregroundStyle(.blue).padding(.horizontal, 10).padding(.vertical, 5).background(Color.blue.opacity(0.12)).cornerRadius(6)
                    Text(current?.title ?? "把时间，留给重要的事").font(.system(size: 25, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    if let t = current { Label("\(t.start) – \(t.end)", systemImage: "clock").foregroundStyle(.secondary).monospacedDigit() }
                    else { Text("查看安排，或添加今天的新任务。").foregroundStyle(.secondary) }
                }
                Spacer(minLength: 10)
                if let t = current {
                    let left = max(0, Int(ceil((Day.moment(now, t.end)!.timeIntervalSince(now)) / 60)))
                    Ring(value: 1 - Double(left) / Double(max(1, t.duration)), title: "\(left)", subtitle: "剩余分钟").frame(width: 100, height: 100)
                }
            }
            if let t = current {
                HStack(spacing: 8) {
                    Button { store.record(t, status: "已完成") } label: { Label("已完成", systemImage: "checkmark") }.buttonStyle(.borderedProminent)
                    Button("部分完成") { store.record(t, status: "部分完成") }.buttonStyle(.bordered)
                    Button("未完成") { store.record(t, status: "未完成") }.buttonStyle(.bordered)
                    Button { editing = t } label: { Image(systemName: "square.and.pencil") }.help("记录备注")
                }.controlSize(.large)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(LinearGradient(colors: [Color.blue.opacity(0.085), Color.blue.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blue.opacity(0.1)))
    }
    private var taskList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("今日安排").font(.title2.weight(.semibold)); Spacer(); Text("\(summary.completed) / \(summary.total) 项完成").font(.caption).foregroundStyle(.secondary) }
            if store.tasks.isEmpty {
                VStack(spacing: 14) { Image(systemName: "calendar.badge.plus").font(.largeTitle).foregroundStyle(.blue); Text("这一天还没有安排").font(.headline); Text("从空白创建，或使用可自由修改的示例计划。").foregroundStyle(.secondary); Button("录入示例计划") { personalConfirm = true }.buttonStyle(.bordered) }.padding(35).frame(maxWidth: .infinity).card()
            } else {
                VStack(spacing: 0) {
                    ForEach(store.tasks) { t in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 2).fill(current?.id == t.id ? Color.blue : .clear).frame(width: 3)
                            Text("\(t.start)–\(t.end)").monospacedDigit().font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) { Text(t.title).font(.system(size: 15, weight: current?.id == t.id ? .semibold : .regular)).foregroundStyle(t.category == "休息" || t.status == "已取消" ? .secondary : .primary).strikethrough(t.status == "已取消"); if !t.note.isEmpty { Text(t.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
                            Spacer(minLength: 4)
                            if t.counts || t.status == "已取消" { Menu { ForEach(["未记录","已完成","部分完成","未完成"], id: \.self) { s in Button(s) { store.record(t, status: s) } } } label: { Text(t.status).font(.caption).foregroundStyle(statusColor(t.status)) }.menuStyle(.borderlessButton).fixedSize() }
                            Button { editing = t } label: { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.buttonStyle(.plain).help("编辑任务")
                        }.padding(.vertical, 13).padding(.trailing, 12).padding(.leading, 4).background(current?.id == t.id ? Color.blue.opacity(0.09) : .clear)
                        .contextMenu { Button("编辑安排") { editing = t }; Button("取消当天任务", role: .destructive) { cancelFuture = false; cancelTask = t }; if t.ruleID != nil { Button("取消当天及以后", role: .destructive) { cancelFuture = true; cancelTask = t } } }
                        if t.id != store.tasks.last?.id { Divider().padding(.horizontal, 14) }
                    }
                }.card()
            }
        }
    }
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("今日进度").font(.headline)
            Ring(value: summary.rate, title: "\(summary.completed)/\(summary.total)", subtitle: summary.total == 0 ? "无任务" : "已完成").frame(width: 135, height: 135).frame(maxWidth: .infinity)
            HStack { metric("部分完成", "\(summary.partial)"); Spacer(); metric("未记录", "\(summary.unrecorded)") }
            Text("休息与取消事项不计入统计").font(.caption2).foregroundStyle(.secondary)
        }.padding(20).card()
    }
    private var weekDays: [Date] { let start = Calendar.current.dateInterval(of: .weekOfYear, for: store.date)!.start; return (0..<7).map { Day.adding($0, to: start) } }
    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本周概览").font(.headline)
            Chart(weekDays, id: \.self) { day in
                let s = Summary(tasks: store.archive.tasks(on: day))
                BarMark(x: .value("日期", day, unit: .day), yStart: .value("起点", 0), yEnd: .value("计划", s.total)).foregroundStyle(Color.blue.opacity(0.09)).cornerRadius(3)
                BarMark(x: .value("日期", day, unit: .day), yStart: .value("起点", 0), yEnd: .value("已完成", s.completed)).foregroundStyle(Color.blue.gradient).cornerRadius(3)
            }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.narrow)) } }.chartYScale(domain: 0...max(1, weekDays.map { Summary(tasks: store.archive.tasks(on: $0)).total }.max() ?? 1)).frame(height: 120)
        }.padding(20).card()
    }
    private var rotationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("轮换计划").font(.headline)
            let rules = store.archive.rules.filter { !$0.rotation.isEmpty && $0.occurrence(on: store.date) != nil }
            if rules.isEmpty { Text("可在任务编辑中设置轮换方向。").font(.caption).foregroundStyle(.secondary) }
            ForEach(rules) { rule in
                Text(rule.occurrence(on: store.date)?.title ?? rule.task.title).font(.subheadline)
                if let next = (1...7).compactMap({ rule.occurrence(on: Day.adding($0, to: store.date)) }).first { Text("下次：\(next.title)").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).card()
    }
    private var plans: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("安排可自由修改；修改重复任务时，可选择仅当天或当天及以后。").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                Text("计划模板").font(.headline)
                HStack { TextField("将当天安排另存为模板", text: $templateName).textFieldStyle(.roundedBorder); Button("保存新模板") { store.saveTemplate(name: templateName); templateName = "" } }
                if !store.templates.isEmpty {
                    HStack { Picker("使用模板", selection: $selectedTemplate) { Text("请选择").tag(""); ForEach(store.templates) { Text($0.name).tag($0.id) } }; DatePicker("应用至", selection: $applyEnd, displayedComponents: .date); Button("预览并应用") { applyConfirm = true }.disabled(selectedTemplate.isEmpty) }
                    ForEach(store.templates) { t in HStack { Text(t.name); Text("\(t.tasks.count) 个时间段").foregroundStyle(.secondary); Spacer(); Button("删除") { deleteTemplate = t } } }
                    Text("编辑模板：应用到空白日期 → 修改当天安排 → 另存为新模板。已有记录不会被覆盖。").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20).card()
            HStack { Text("任务间休息"); Picker("时长", selection: $breakMinutes) { Text("5 分钟").tag(5); Text("10 分钟").tag(10); Text("15 分钟").tag(15); Text("20 分钟").tag(20); Text("30 分钟").tag(30) }.frame(width: 145); Button("在当天空隙插入休息") { store.insertBreaks(minutes: breakMinutes) }; Spacer() }
            taskList
        }.onAppear { applyEnd = store.date }
    }
    private var periodDays: [Date] {
        if statsPeriod == "日" { return [store.date] }
        let c = Calendar.current, interval = c.dateInterval(of: statsPeriod == "周" ? .weekOfYear : .month, for: store.date)!
        let count = c.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
        return (0..<count).map { Day.adding($0, to: interval.start) }
    }
    private func filtered(_ day: Date) -> [TaskItem] { store.archive.tasks(on: day).filter { category == "全部" || $0.category == category } }
    private var statistics: some View {
        let all = periodDays.flatMap { filtered($0) }, s = Summary(tasks: all)
        return VStack(alignment: .leading, spacing: 22) {
            HStack { Picker("周期", selection: $statsPeriod) { ForEach(["日","周","月"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(width: 220); Spacer(); Picker("分类", selection: $category) { Text("全部").tag("全部"); ForEach(Array(Set(store.archive.days.values.flatMap { $0 }.map(\.category) + store.archive.rules.map { $0.task.category })).sorted(), id: \.self) { Text($0).tag($0) } }.frame(width: 200) }
            HStack { metric("已完成", "\(s.completed) / \(s.total)"); Spacer(); metric("部分完成", "\(s.partial)"); Spacer(); metric("未完成", "\(s.missed)"); Spacer(); metric("未记录", "\(s.unrecorded)"); Spacer(); metric("完成率", s.total == 0 ? "无任务" : "\(Int(s.rate * 100))%") }.padding(24).card()
            Text("包含所选周期全部计划；执行结果截至当前。计划时长：\(s.minutes / 60) 小时 \(s.minutes % 60) 分钟，不代表实际投入。").font(.caption).foregroundStyle(.secondary)
            if statsPeriod == "月" { monthCalendar }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) { Label("计划", systemImage: "square.fill").foregroundStyle(Color.blue.opacity(0.35)); Label("已完成", systemImage: "square.fill").foregroundStyle(.blue) }.font(.caption)
                Chart(periodDays, id: \.self) { day in
                    let x = Summary(tasks: filtered(day))
                    BarMark(x: .value("日期", day, unit: .day), yStart: .value("起点", 0), yEnd: .value("计划", x.total)).foregroundStyle(Color.blue.opacity(0.09)).cornerRadius(4)
                    BarMark(x: .value("日期", day, unit: .day), yStart: .value("起点", 0), yEnd: .value("已完成", x.completed)).foregroundStyle(Color.blue.gradient).cornerRadius(4)
                }.chartYScale(domain: 0...max(1, periodDays.map { Summary(tasks: filtered($0)).total }.max() ?? 1)).frame(height: 190)
            }.padding(20).card()
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) { Text("分类概览").font(.headline); ForEach(s.categories.keys.sorted(), id: \.self) { name in let items = all.filter { $0.category == name && $0.counts && $0.status != "已取消" }; HStack { Text(name); Spacer(); Text("\(items.filter { $0.status == "已完成" }.count) / \(items.count) 项") } } }.padding(20).frame(maxWidth: .infinity, alignment: .leading).card()
                VStack(alignment: .leading, spacing: 14) { Text("每日记录").font(.headline); ForEach(periodDays, id: \.self) { d in let x = Summary(tasks: filtered(d)); Button { store.date = d; page = "今天" } label: { HStack { Text(d.formatted(.dateTime.month().day())); Spacer(); Text(x.total == 0 ? "无任务" : "\(x.completed) / \(x.total)"); Image(systemName: "chevron.right") } }.buttonStyle(.plain) } }.padding(20).frame(maxWidth: .infinity, alignment: .leading).card()
            }
        }
    }
    private var monthCalendar: some View {
        let offset = (Calendar.current.component(.weekday, from: periodDays[0]) - Calendar.current.firstWeekday + 7) % 7
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 60) }
            ForEach(periodDays, id: \.self) { d in let x = Summary(tasks: filtered(d)); Button { store.date = d; page = "今天" } label: { VStack(spacing: 5) { Text(d.formatted(.dateTime.day())).font(.headline); Text(x.total == 0 ? "—" : "\(x.completed)/\(x.total)").font(.caption) }.frame(maxWidth: .infinity).frame(height: 60).background(Color.blue.opacity(0.04 + x.rate * 0.2)).cornerRadius(9) }.buttonStyle(.plain) }
        }.padding(16).card()
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 16) {
                Label("提醒", systemImage: "bell.badge").font(.headline)
                Toggle("开启任务提醒", isOn: $store.enabled); Toggle("通知提示音", isOn: $store.sound)
                HStack { Text("系统权限：\(store.notificationStatus)").foregroundStyle(.secondary); Spacer(); Button("开启通知") { store.requestPermission() }; Button("测试提醒") { store.testNotification() } }
                Text("关闭窗口后仍在菜单栏后台运行。彻底退出后不保证提醒；系统专注模式可能静音通知。应用会更新未来最近 60 条提醒，请保持后台运行。").font(.caption).foregroundStyle(.secondary)
            }.padding(22).card()
            VStack(alignment: .leading, spacing: 16) {
                Label("启动与后台", systemImage: "power").font(.headline)
                Toggle("登录时启动", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { store.setLogin($0) }))
                Text("本机测试版未经过 Apple 公证；登录启动是否可用由系统权限决定。关闭窗口不会退出，退出请使用菜单栏或 ⌘Q。").font(.caption).foregroundStyle(.secondary)
            }.padding(22).card()
            VStack(alignment: .leading, spacing: 16) {
                Label("数据与备份", systemImage: "externaldrive").font(.headline)
                HStack { Button("导出完整备份") { store.exportBackup() }; Button("从备份恢复…") { store.restoreBackup() }; Button("打开数据目录") { NSWorkspace.shared.open(store.url.deletingLastPathComponent()) } }
                Text(store.url.path).font(.caption).textSelection(.enabled).foregroundStyle(.secondary)
                Text("数据仅保存在本机。恢复前自动保留当前文件，建议定期导出备份。").font(.caption).foregroundStyle(.secondary)
            }.padding(22).card()
            Text("时间安排管家 · 0.1.0 · macOS 本地版").font(.caption).foregroundStyle(.secondary)
        }.onAppear { store.checkPermission() }
    }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(size: 24, weight: .semibold)).monospacedDigit() } }
    private func statusColor(_ status: String) -> Color { switch status { case "已完成": return .green; case "部分完成": return .orange; case "未完成": return .red; default: return .secondary } }
}
struct Ring: View {
    var value: Double, title: String, subtitle: String
    var body: some View { ZStack { Circle().stroke(Color.primary.opacity(0.07), lineWidth: 8); Circle().trim(from: 0, to: min(1, max(0, value))).stroke(Color.blue.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90)); VStack(spacing: 5) { Text(title).font(.system(size: 28, weight: .semibold)).minimumScaleFactor(0.5); Text(subtitle).font(.caption).foregroundStyle(.secondary) } }.padding(5) }
}
extension View {
    func card() -> some View { self.background(Color(nsColor: .controlBackgroundColor)).cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.055))).shadow(color: .black.opacity(0.025), radius: 6, y: 2) }
}
