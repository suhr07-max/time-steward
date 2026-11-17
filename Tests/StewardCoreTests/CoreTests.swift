import Foundation
import StewardCore

func XCTAssertTrue(_ value: Bool) { precondition(value, "Expected true") }
func XCTAssertFalse(_ value: Bool) { precondition(!value, "Expected false") }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil, "Expected nil") }
func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil, "Expected non-nil") }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Values differ: \(a) != \(b)") }
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a != b, "Expected unequal values") }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double) { precondition(abs(a - b) <= accuracy, "Values differ") }

final class CoreTests {
    let monday = Day.date("2026-11-16")!
    func testRotationSkipsNonApplicableDays() {
        let r = Rule(task: TaskItem(title: "项目"), from: "2026-11-16", weekdays: [2,3,4,5,6], rotation: ["A","B","C","D"])
        XCTAssertEqual(r.occurrence(on: monday)?.title, "项目 · A")
        XCTAssertNil(r.occurrence(on: Day.adding(5, to: monday)))
        XCTAssertEqual(r.occurrence(on: Day.adding(7, to: monday))?.title, "项目 · B")
        XCTAssertEqual(r.occurrence(on: Day.adding(8, to: monday))?.title, "项目 · C")
    }
    func testDailyRotationAndStableIdentity() {
        let r = Rule(task: TaskItem(title: "项目"), from: "2026-11-16", rotation: ExamplePlan.directions)
        XCTAssertEqual(r.occurrence(on: Day.adding(4, to: monday))?.title, "项目 · 写作实验")
        XCTAssertEqual(r.occurrence(on: monday)?.id, r.occurrence(on: monday)?.id)
        XCTAssertNotEqual(r.occurrence(on: monday)?.id, r.occurrence(on: Day.adding(1, to: monday))?.id)
    }
    func testFreezePreservesHistoryAfterRuleChanges() {
        var a = Archive(); a.rules = [Rule(task: TaskItem(title: "原计划"), from: "2026-11-16")]
        a.freezePast(until: monday)
        a.rules[0].task.title = "新计划"
        XCTAssertEqual(a.tasks(on: monday)[0].title, "原计划")
        XCTAssertEqual(a.tasks(on: Day.adding(1, to: monday))[0].title, "新计划")
        XCTAssertEqual(a.tasks(on: monday)[0].status, "未记录")
    }
    func testSummaryExcludesRestAndCancellation() {
        var done = TaskItem(title: "已完成"); done.status = "已完成"
        var partial = TaskItem(title: "部分"); partial.status = "部分完成"
        var rest = TaskItem(title: "休息"); rest.counts = false
        var cancelled = TaskItem(title: "取消"); cancelled.status = "已取消"
        let s = Summary(tasks: [done,partial,rest,cancelled,TaskItem(title: "待记录")])
        XCTAssertEqual(s.total, 3); XCTAssertEqual(s.completed, 1); XCTAssertEqual(s.partial, 1); XCTAssertEqual(s.unrecorded, 1); XCTAssertEqual(s.rate, 1.0/3.0, accuracy: 0.001)
    }
    func testLegacyMigrationAndRoundTrip() throws {
        let data = Data(#"{"days":{"2026-11-16":[{"id":"legacy-id","title":"旧任务","start":"09:00","end":"10:00","counts":true,"status":"已完成","note":"保留"}]}}"#.utf8)
        let a = try JSONDecoder().decode(Archive.self, from: data)
        XCTAssertNil(a.validation()); XCTAssertEqual(a.tasks(on: monday).first?.note, "保留")
        let b = try JSONDecoder().decode(Archive.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(b.tasks(on: monday), a.tasks(on: monday))
    }
    func testTimeValidationAndOverlap() {
        let a = TaskItem(title: "A", start: "09:00", end: "10:00")
        XCTAssertTrue(a.valid)
        XCTAssertFalse(a.overlaps(TaskItem(title: "B", start: "10:00", end: "11:00")))
        XCTAssertTrue(a.overlaps(TaskItem(title: "C", start: "09:59", end: "11:00")))
        XCTAssertFalse(TaskItem(title: "D", start: "25:00", end: "26:00").valid)
        XCTAssertFalse(TaskItem(title: "D", start: "10:00", end: "09:00").valid)
    }
    func testExamplePlanDurationsAndNoOverlap() {
        let tasks = ExamplePlan.tasks
        XCTAssertEqual(tasks.count, 16)
        XCTAssertEqual(tasks.filter(\.counts).reduce(0) { $0 + $1.duration }, 600)
        for pair in zip(tasks, tasks.dropFirst()) { XCTAssertFalse(pair.0.overlaps(pair.1)) }
        XCTAssertTrue(tasks.allSatisfy { $0.status == "未记录" })
    }
    func testEffectiveEndStopsRule() {
        var rule = Rule(task: TaskItem(title: "任务"), from: "2026-11-16"); rule.through = "2026-11-17"
        XCTAssertNil(rule.occurrence(on: Day.adding(-1, to: monday)))
        XCTAssertNotNil(rule.occurrence(on: Day.adding(1, to: monday)))
        XCTAssertNil(rule.occurrence(on: Day.adding(2, to: monday)))
    }
}

@main struct RunChecks {
    static func main() throws {
        let tests = CoreTests()
        tests.testRotationSkipsNonApplicableDays()
        tests.testDailyRotationAndStableIdentity()
        tests.testFreezePreservesHistoryAfterRuleChanges()
        tests.testSummaryExcludesRestAndCancellation()
        try tests.testLegacyMigrationAndRoundTrip()
        tests.testTimeValidationAndOverlap()
        tests.testExamplePlanDurationsAndNoOverlap()
        tests.testEffectiveEndStopsRule()
        print("PASS: 8 core checks (rotation, history, statistics, migration, time validation, example plan).")
        if let i = CommandLine.arguments.firstIndex(of: "--archive"), CommandLine.arguments.count > i + 1 {
            let a = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i+1])))
            XCTAssertNil(a.validation())
            let today = Date(), tasks = a.tasks(on: today), summary = Summary(tasks: tasks)
            print("Archive verified: \(tasks.count) slots, \(summary.total) counted tasks, \(summary.completed) complete, \(summary.unrecorded) unrecorded.")
            for n in 0..<4 { let d = Day.adding(n, to: today); print("\(Day.key(d)): \(a.tasks(on: d).first(where: { $0.category == "项目" })?.title ?? "—")") }
        }
    }
}
