import SwiftUI
import UserNotifications

struct DDLTask: Identifiable, Codable, Hashable {
    var id = UUID()
    var subject: String
    var title: String
    var dueDate: Date
    var isCompleted = false
    var createdAt = Date()
}

@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [DDLTask] = [] {
        didSet { save() }
    }

    private let storageKey = "ddl-manager.tasks.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([DDLTask].self, from: data) {
            tasks = saved
        }
        requestNotificationPermission()
        refreshNotifications()
    }

    var pending: [DDLTask] {
        tasks.filter { !$0.isCompleted }.sorted { $0.dueDate < $1.dueDate }
    }

    var completed: [DDLTask] {
        tasks.filter(\.isCompleted).sorted { $0.dueDate > $1.dueDate }
    }

    func add(subject: String, title: String, dueDate: Date) {
        let task = DDLTask(subject: subject, title: title, dueDate: dueDate)
        tasks.append(task)
        scheduleNotifications(for: task)
    }

    func toggle(_ task: DDLTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted.toggle()
        if tasks[index].isCompleted {
            removeNotifications(for: task)
        } else {
            scheduleNotifications(for: tasks[index])
        }
    }

    func remove(_ task: DDLTask) {
        tasks.removeAll { $0.id == task.id }
        removeNotifications(for: task)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func refreshNotifications() {
        for task in pending { scheduleNotifications(for: task) }
    }

    private func scheduleNotifications(for task: DDLTask) {
        removeNotifications(for: task)
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let reminders: [(String, Date, String)] = [
            ("early", calendar.date(byAdding: .day, value: -1, to: task.dueDate) ?? task.dueDate,
             "明天截止：\(task.title)"),
            ("due", task.dueDate, "DDL 到时间了：\(task.title)")
        ]

        for (suffix, date, message) in reminders where date > Date() {
            let content = UNMutableNotificationContent()
            content.title = task.subject
            content.body = message
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "ddl.\(task.id.uuidString).\(suffix)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func removeNotifications(for task: DDLTask) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "ddl.\(task.id.uuidString).early",
            "ddl.\(task.id.uuidString).due"
        ])
    }
}

enum DeadlineParser {
    static func parse(_ raw: String, now: Date = Date()) -> Date? {
        let text = raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "：", with: ":")
        guard !text.isEmpty else { return nil }

        let calendar = Calendar.current
        let time = parseTime(text) ?? (23, 59)
        var targetDay: Date?

        if text.contains("今天") {
            targetDay = now
        } else if text.contains("明天") {
            targetDay = calendar.date(byAdding: .day, value: 1, to: now)
        } else if text.contains("后天") {
            targetDay = calendar.date(byAdding: .day, value: 2, to: now)
        } else if text.contains("一周后") || text.contains("下周") {
            targetDay = calendar.date(byAdding: .day, value: 7, to: now)
        } else if text.contains("两周后") || text.contains("二周后") {
            targetDay = calendar.date(byAdding: .day, value: 14, to: now)
        } else if let days = matchedNumber(in: text, pattern: #"(\d+)天后"#) {
            targetDay = calendar.date(byAdding: .day, value: days, to: now)
        } else if let weeks = matchedNumber(in: text, pattern: #"(\d+)周后"#) {
            targetDay = calendar.date(byAdding: .day, value: weeks * 7, to: now)
        }

        if let targetDay {
            return calendar.date(bySettingHour: time.0, minute: time.1, second: 0, of: targetDay)
        }

        let formats = ["yyyy-MM-ddHH:mm", "yyyy/M/dHH:mm", "yyyy-MM-dd", "yyyy/M/d"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                if format.contains("HH:mm") { return date }
                return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: date)
            }
        }
        return nil
    }

    private static func parseTime(_ text: String) -> (Int, Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              let minuteRange = Range(match.range(at: 2), in: text),
              let hour = Int(text[hourRange]), let minute = Int(text[minuteRange]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private static func matchedNumber(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }
}

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @State private var subject = ""
    @State private var title = ""
    @State private var deadlineText = "一周后 23:59"
    @FocusState private var focusedField: Field?

    enum Field { case subject, title, deadline }

    private var parsedDate: Date? { DeadlineParser.parse(deadlineText) }
    private var canSave: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        parsedDate != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("添加 DDL")
                    .font(.title2.bold())
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("学科").font(.caption).foregroundStyle(.secondary)
                TextField("例如：数据结构", text: $subject)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .subject)
                    .onSubmit { focusedField = .title }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("任务").font(.caption).foregroundStyle(.secondary)
                TextField("例如：完成实验报告", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)
                    .onSubmit { focusedField = .deadline }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("截止时间").font(.caption).foregroundStyle(.secondary)
                TextField("一周后 23:59", text: $deadlineText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .deadline)

                HStack(spacing: 7) {
                    quickButton("今晚")
                    quickButton("明天 23:59")
                    quickButton("3天后 23:59")
                    quickButton("一周后 23:59")
                }

                if let date = parsedDate {
                    Label(date.formatted(date: .long, time: .shortened), systemImage: "calendar.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("可输入：明天、一周后、3天后、2026-10-01 23:59", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Button {
                guard let dueDate = parsedDate else { return }
                store.add(
                    subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    dueDate: dueDate
                )
                dismiss()
            } label: {
                Text("加入清单")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSave)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(22)
        .frame(width: 420)
        .onAppear { focusedField = .subject }
    }

    private func quickButton(_ value: String) -> some View {
        Button(value.replacingOccurrences(of: " 23:59", with: "")) {
            deadlineText = value
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct TaskRow: View {
    let task: DDLTask
    let toggle: () -> Void
    let remove: () -> Void

    private var urgencyColor: Color {
        let remaining = task.dueDate.timeIntervalSinceNow
        if remaining < 0 { return .red }
        if remaining < 86_400 { return .orange }
        if remaining < 3 * 86_400 { return .yellow }
        return .blue
    }

    private var remainingText: String {
        if task.isCompleted { return "已完成" }
        let interval = task.dueDate.timeIntervalSinceNow
        if interval < 0 {
            let days = max(1, Int(abs(interval) / 86_400))
            return "已逾期 \(days) 天"
        }
        let days = Int(interval / 86_400)
        let hours = Int(interval.truncatingRemainder(dividingBy: 86_400) / 3600)
        if days > 0 { return "还剩 \(days) 天 \(hours) 小时" }
        if hours > 0 { return "还剩 \(hours) 小时" }
        return "不到 1 小时"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : urgencyColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(task.subject)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(urgencyColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(urgencyColor)
                    Spacer()
                    Text(remainingText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(urgencyColor)
                }

                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                Text(task.dueDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button(task.isCompleted ? "恢复任务" : "标记完成", action: toggle)
            Divider()
            Button("移出清单", role: .destructive, action: remove)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var showingAdd = false
    @State private var showCompleted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.pending.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.pending) { task in
                            TaskRow(task: task) {
                                withAnimation { store.toggle(task) }
                            } remove: {
                                withAnimation { store.remove(task) }
                            }
                        }
                    }

                    if !store.completed.isEmpty {
                        DisclosureGroup(isExpanded: $showCompleted) {
                            VStack(spacing: 10) {
                                ForEach(store.completed) { task in
                                    TaskRow(task: task) {
                                        withAnimation { store.toggle(task) }
                                    } remove: {
                                        withAnimation { store.remove(task) }
                                    }
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("已完成 · \(store.completed.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 5)
                    }
                }
                .padding(14)
            }

            Divider()
            footer
        }
        .frame(width: 400, height: 540)
        .sheet(isPresented: $showingAdd) {
            AddTaskView().environmentObject(store)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.gradient)
                Image(systemName: "checklist.checked")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("DDL 清单").font(.headline)
                Text(store.pending.isEmpty ? "今天也很轻松" : "还有 \(store.pending.count) 项待完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.bold())
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .help("添加 DDL")
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("没有待完成的 DDL")
                .font(.headline)
            Text("点右上角的 +，把下一个截止日期挂起来。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("添加第一项") { showingAdd = true }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private var footer: some View {
        HStack {
            Label("数据只保存在本机", systemImage: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

@main
struct DDLManagerApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checklist.checked")
                if !store.pending.isEmpty {
                    Text("\(store.pending.count)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
