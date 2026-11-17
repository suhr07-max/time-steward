import SwiftUI
import StewardCore

struct Editor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store
    @State var task: TaskItem
    @State private var repeating = false
    @State private var weekdays: Set<Int> = []
    @State private var rotationText = ""
    @State private var scope = "仅当天"
    @State private var validation = ""
    @State private var loaded = false
    let weekdayNames = [(2,"一"),(3,"二"),(4,"三"),(5,"四"),(6,"五"),(7,"六"),(1,"日")]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("编辑安排").font(.title2.bold()); Spacer(); Text(store.date, style: .date).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("任务名称", text: $task.title)
                    HStack { field("开始时间", text: $task.start); Text("—").padding(.top, 16); field("结束时间", text: $task.end) }
                    HStack {
                        VStack(alignment: .leading) { Text("分类").font(.caption).foregroundStyle(.secondary); TextField("工作、学习、项目…", text: $task.category) }
                        Toggle("计入完成统计", isOn: $task.counts)
                    }
                    Text("内容与子项").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $task.detail).frame(height: 65).padding(5).background(.quaternary.opacity(0.3)).cornerRadius(8)
                    Divider()
                    HStack { Toggle("开始提醒", isOn: $task.remind); Spacer(); Toggle("结束提醒", isOn: $task.endReminder) }
                    if task.remind { Picker("提前提醒", selection: $task.advance) { Text("到点提醒").tag(0); Text("提前 5 分钟").tag(5); Text("提前 10 分钟").tag(10); Text("提前 15 分钟").tag(15); Text("提前 30 分钟").tag(30) } }
                    Divider()
                    if task.ruleID != nil { Picker("修改范围", selection: $scope) { Text("仅当天").tag("仅当天"); Text("当天及以后").tag("当天及以后") }.pickerStyle(.segmented) }
                    if task.ruleID == nil || scope == "当天及以后" {
                        Toggle("重复安排", isOn: $repeating)
                        if repeating {
                            Text("不选择星期表示每天重复").font(.caption).foregroundStyle(.secondary)
                            HStack { ForEach(weekdayNames, id: \.0) { number, label in Button(label) { if weekdays.contains(number) { weekdays.remove(number) } else { weekdays.insert(number) } }.buttonStyle(.bordered).tint(weekdays.contains(number) ? .blue : .gray) } }
                            Text("轮换方向（可选，每行一个，按适用日期推进）").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $rotationText).frame(height: 65).padding(5).background(.quaternary.opacity(0.3)).cornerRadius(8)
                        }
                    }
                    Divider()
                    Picker("完成状态", selection: $task.status) { ForEach(["未记录","已完成","部分完成","未完成","已取消"], id: \.self) { Text($0) } }
                    TextField("执行备注（选填）", text: $task.note)
                    if scope == "当天及以后" || repeating && task.ruleID == nil { Text("重复计划的未来任务将从“未记录”开始；编辑执行结果请选择“仅当天”。").font(.caption).foregroundStyle(.secondary) }
                    if !validation.isEmpty { Text(validation).foregroundStyle(.red).font(.caption) }
                }.padding(2)
            }
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("保存安排") {
                if task.category.trimmingCharacters(in: .whitespaces).isEmpty { task.category = "其他" }
                let rotation = rotationText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let future = scope == "当天及以后"
                if task.ruleID != nil && future && !repeating { validation = "若要停止重复，请在任务菜单选择“取消当天及以后”。"; return }
                if store.saveTask(task, repeating: repeating, weekdays: Array(weekdays).sorted(), rotation: rotation, future: future) { dismiss() } else { validation = store.message; store.message = "" }
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(store.readOnly) }
        }.padding(26).frame(width: 500, height: 740).textFieldStyle(.roundedBorder)
        .onAppear {
            guard !loaded else { return }; loaded = true
            if let rule = store.archive.rules.first(where: { $0.id == task.ruleID }) { repeating = true; weekdays = Set(rule.weekdays); rotationText = rule.rotation.joined(separator: "\n") }
        }
        .onChange(of: scope) { value in
            if value == "当天及以后", let rule = store.archive.rules.first(where: { $0.id == task.ruleID }) { task.title = rule.task.title }
        }
    }
    private func field(_ label: String, text: Binding<String>) -> some View { VStack(alignment: .leading) { Text(label + " HH:mm").font(.caption).foregroundStyle(.secondary); TextField("09:00", text: text) } }
}
