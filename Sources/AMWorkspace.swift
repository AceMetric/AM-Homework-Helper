import AppKit
import SwiftUI

// One semantic palette for SwiftUI and the existing AppKit drawing layer.
@objc(AMAppearance) public final class AMAppearance:NSObject {
    @objc public static var canvas:NSColor {.windowBackgroundColor}
    @objc public static var surface:NSColor {.controlBackgroundColor}
    @objc public static var sidebar:NSColor {.windowBackgroundColor}
    @objc public static var separator:NSColor {.separatorColor}
    @objc public static var ink:NSColor {.labelColor}
    @objc public static var muted:NSColor {.secondaryLabelColor}
    @objc public static var accent:NSColor {.controlAccentColor}
    @objc public static var selection:NSColor {accent.withAlphaComponent(0.12)}
}
// Preserve DisclosureGroup semantics while making its whole header a target.
private struct WorkspaceDisclosureStyle:DisclosureGroupStyle {
    func makeBody(configuration:Configuration)->some View {
        VStack(alignment:.leading,spacing:8) {
            Button {configuration.isExpanded.toggle()} label:{
                HStack(spacing:6) {
                    Image(systemName:configuration.isExpanded ? "chevron.down":"chevron.right")
                        .font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary).frame(width:12)
                    configuration.label
                    Spacer(minLength:0)
                }.frame(maxWidth:.infinity,minHeight:34,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(configuration.isExpanded ? "已展开":"已收起")
            if configuration.isExpanded {configuration.content.padding(.leading,18)}
        }
    }
}
private struct WorkspaceDisclosure<Content:View>:View {
    let title:String
    let content:Content
    init(_ title:String,@ViewBuilder content:()->Content){self.title=title;self.content=content()}
    var body:some View {DisclosureGroup(title){content}.disclosureGroupStyle(WorkspaceDisclosureStyle())}
}
private struct WorkspaceExpandedSection<Content:View>:View {
    let title:String
    let content:Content
    init(_ title:String,@ViewBuilder content:()->Content){self.title=title;self.content=content()}
    var body:some View {VStack(alignment:.leading,spacing:10){Text(title).font(.subheadline.weight(.medium));content}.frame(maxWidth:.infinity,alignment:.leading)}
}
// Use the system glass button implementations; older OS/SDK lanes retain native controls.
private extension View {
    func amPrimaryAction()->some View {self.buttonStyle(.borderedProminent)}
    func amSecondaryActions()->some View {self.buttonStyle(.bordered)}
}
private struct WorkspaceSection<Content:View>:View {
    let title:String
    let content:Content
    init(_ title:String,@ViewBuilder content:()->Content){self.title=title;self.content=content()}
    var body:some View {
        GroupBox {content.frame(maxWidth:.infinity,alignment:.leading).padding(4)} label:{Text(title).font(.subheadline.weight(.medium))}
            .frame(maxWidth:.infinity,alignment:.leading)
    }
}

private func string(_ record: NSDictionary, _ key: String) -> String { record[key] as? String ?? "" }
private func flag(_ record: NSDictionary, _ key: String) -> Bool { (record[key] as? NSNumber)?.boolValue ?? false }
private func identifier(_ record: NSDictionary) -> String { string(record, "id") }
func suggestedNotes(_ record:NSDictionary)->String {
    let summary=(record["sourceSummary"] as? String ?? string(record,"summary")).trimmingCharacters(in:.whitespacesAndNewlines)
    let requirements=(record["sourceRequirements"] as? String ?? string(record,"submissionRequirements")).trimmingCharacters(in:.whitespacesAndNewlines)
    var parts:[String]=[]
    if !summary.isEmpty {parts.append("作业内容\n"+summary)}
    if !requirements.isEmpty && requirements != summary {parts.append("提交要求\n"+requirements)}
    return parts.joined(separator:"\n\n")
}
private func batchDate(_ date:Date,zone:String)->String {
    let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd HH:mm z"
    formatter.timeZone=TimeZone(identifier:zone) ?? .current
    return formatter.string(from:date)
}
func isRepeatedWorkspaceEvent(_ event:NSEvent?)->Bool {
    guard let event else{return false}
    if event.type == .leftMouseUp || event.type == .leftMouseDown {return event.clickCount>1}
    return event.type == .keyDown && event.isARepeat
}

// Objective-C controllers mutate their dictionaries as operations progress. Never
// use those objects as SwiftUI identity, or let old views observe later mutations.
private func workspaceSnapshot(_ value: Any) -> Any {
    if let dictionary = value as? NSDictionary {
        var result: [String: Any] = [:]
        for case let key as String in dictionary.allKeys {
            if let item = dictionary[key] { result[key] = workspaceSnapshot(item) }
        }
        return result as NSDictionary
    }
    if let array = value as? NSArray { return array.map(workspaceSnapshot) as NSArray }
    if let text = value as? NSString { return String(text) }
    return value
}
func workspaceRecords(_ records: [NSDictionary]) -> [NSDictionary] {
    records.map { workspaceSnapshot($0) as! NSDictionary }
}
struct WorkspaceRow: Identifiable {
    let id: String
    let record: NSDictionary
}
func workspaceRows(_ records: [NSDictionary], key: String = "id") -> [WorkspaceRow] {
    var occurrences: [String: Int] = [:]
    return records.enumerated().map { index, record in
        let value = string(record, key)
        let base = value.isEmpty ? "position:\(index)" : "\(key):\(value.utf8.count):\(value)"
        let occurrence = occurrences[base, default: 0]
        occurrences[base] = occurrence + 1
        // Duplicate/missing source identifiers still get distinct presentation IDs.
        // Operation targets remain the original source IDs, never these row IDs.
        return WorkspaceRow(id: "\(base):\(occurrence)", record: record)
    }
}

struct ReviewBatchItem: Identifiable {
    let id: String
    let title: String
    let due: Date?
    let course: String
    let timeZone: String
    let basis: String
    let reason: String
    let relative: Bool
    let payload: NSDictionary?
}

@MainActor
final class ReviewState: ObservableObject {
    @Published var records: [NSDictionary] = []
    @Published var selected = ""
    @Published var checked: Set<String> = []
    @Published var query = "" { didSet { pruneChecks(); batchPreview=nil } }
    @Published var searchToken = 0
    @Published var title = ""
    @Published var subject = ""
    @Published var priority = 0
    @Published var notes = ""
    @Published var date = Date()
    @Published var hasDate = false
    @Published var dateConfirmed = false
    @Published var reminders = true
    @Published var reminderOffsets: Set<Int> = [10080,4320,1440,60,0]
    private var baseline:NSDictionary=[:]
    private var savedValues:NSDictionary {
        ["title":title.trimmingCharacters(in:.whitespacesAndNewlines),"notes":notes,"subject":subject.trimmingCharacters(in:.whitespacesAndNewlines),"priority":priority,"date":hasDate ? date as Any:NSNull(),"hasDate":hasDate,"dateConfirmed":dateConfirmed,"reminders":reminders ? reminderOffsets.sorted():[]] as NSDictionary
    }
    var dirty:Bool {get{!savedValues.isEqual(baseline)}set{if !newValue {baseline=savedValues}}}
    @Published var message = ""
    @Published var failed = false
    @Published var saving = false
    @Published var paused = false
    @Published var batchPreview: [ReviewBatchItem]?
    var activeRecord: NSDictionary?
    var decision:(([NSDictionary],Bool)->String)?
    @Published var lastDeleted:[NSDictionary]=[]
    var save: (([NSDictionary]) -> String)?
    var sourceResolver: ((String)->NSDictionary?)?
    var didSave: (() -> Void)?
    var originalTitle = "", originalNotes = ""
    init(){baseline=savedValues}
    var current: NSDictionary? { activeRecord }
    var visible: [NSDictionary] {
        records.filter { string($0,"reviewStatus") != "已导入" && (query.isEmpty || [string($0,"suggestedTitle"),string($0,"title"),string($0,"repository"),string($0,"path")].joined(separator:" ").localizedCaseInsensitiveContains(query)) }
    }
    var disabledReason: String {
        if let current,flag(current,"reviewDeleted") {return "该建议已删除，可恢复后再审核。"}
        return saving ? "正在保存，请稍候…" : paused ? "课程操作正在进行，请等待结束后保存。" : current == nil ? "请先选择一项待审核作业。" : ""
    }
    var sourceChanged: Bool {
        guard let current else {return false}
        guard let latest=latestSource(identifier(current)) else {return true}
        return ["blobSHA","kind","dateText","due","suggestedDue","needsDate","needsTime"].contains { key in
            !NSDictionary(dictionary:["value":current[key] ?? NSNull()]).isEqual(to:["value":latest[key] ?? NSNull()])
        }
    }
    func delete(_ ids:Set<String> = []) {
        guard !isRepeatedWorkspaceEvent(NSApp?.currentEvent) else{return}
        let targets=ids.isEmpty ? (checked.isEmpty ? Set([selected]):checked):ids
        let rows=records.filter{targets.contains(identifier($0)) && !flag($0,"reviewDeleted") && string($0,"reviewStatus") != "已导入"}
        guard !rows.isEmpty,!saving,!paused else{return}
        if targets.contains(selected),!resolve(){return}
        saving=true
        let problem=decision?(rows,true) ?? "删除接口不可用，请重试。"
        saving=false
        guard problem.isEmpty else{reject(problem);return}
        lastDeleted=workspaceRecords(rows);checked.subtract(targets);batchPreview=nil
        if targets.contains(selected){clearDraft()}
        records.removeAll{targets.contains(identifier($0))}
        if current==nil,let next=visible.first{load(next)}
        failed=false;message="已删除 \(rows.count) 项审核建议。";didSave?()
    }
    func restore(_ rows:[NSDictionary]) {
        guard !rows.isEmpty,!saving,!paused else{return}
        saving=true;let problem=decision?(rows,false) ?? "恢复接口不可用，请重试。";saving=false
        guard problem.isEmpty else{reject(problem);return}
        lastDeleted=[];if !dirty {clearDraft()};checked=[];batchPreview=nil
        records.removeAll{row in flag(row,"reviewDeleted") && rows.contains{identifier($0)==identifier(row)}}
        if current==nil,let next=visible.first{load(next)}
        failed=false;message="已恢复审核建议。";didSave?()
    }
    func latestSource(_ id:String)->NSDictionary? {sourceResolver != nil ? sourceResolver?(id) : records.first{identifier($0)==id}}
    func pruneChecks(){checked.formIntersection(Set(visible.map(identifier)))}
    func selectAll(){checked=Set(visible.map(identifier))}
    func clearChecks(){checked=[];batchPreview=nil}
    func refresh(_ records: [NSDictionary]) {
        let snapshot=workspaceRecords(records)
        self.records = snapshot
        pruneChecks()
        // Do not erase a draft while the save callback refreshes the controller.
        if !dirty && !saving {
            if let record = snapshot.first(where: {identifier($0) == selected}) { load(record) }
            else if let first = snapshot.first { load(first) }
            else { clearDraft() }
        }
    }
    func clearDraft(){selected="";activeRecord=nil;title="";notes="";hasDate=false;dateConfirmed=false;dirty=false}
    func suggestion(_ record:NSDictionary)->Date? {
        let basis=record["dateBasis"] as? NSDictionary
        guard !flag(record,"needsTime"), (record["warnings"] as? [String] ?? []).isEmpty,
              basis?["date"] is Date, !string(basis ?? [:],"commit").isEmpty else{return nil}
        return record["suggestedDue"] as? Date
    }
    func load(_ record: NSDictionary) {
        activeRecord = record; selected = identifier(record)
        let task = record["existingTask"] as? NSDictionary
        title = task?["title"] as? String ?? (string(record,"suggestedTitle").isEmpty ? string(record,"title") : string(record,"suggestedTitle"))
        notes = task?["notes"] as? String ?? (string(record,"sourceType")=="local" ? string(record,"notes"):suggestedNotes(record))
        let suggestion=suggestion(record)
        if let value = task?["due"] as? Date { date = value; hasDate = true }
        else if let value = record["due"] as? Date { date = value; hasDate = true }
        else if let suggestion { date = suggestion; hasDate = true }
        else if let value = record["dateOnly"] as? String {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(identifier:string(record,"timeZone")) ?? .current
            date = formatter.date(from:value) ?? Date(); hasDate = false
        } else { date = Date(); hasDate = false }
        dateConfirmed = hasDate && !flag(record,"needsDate") && !flag(record,"needsTime") && (record["warnings"] as? [String] ?? []).isEmpty
        if task==nil, suggestion != nil { dateConfirmed=true }
        if task?["due"] is Date { dateConfirmed=true }
        reminders = ((task?["reminderOffsets"] as? [NSNumber])?.isEmpty == false) || task == nil
        reminderOffsets = Set((task?["reminderOffsets"] as? [NSNumber])?.map(\.intValue) ?? [10080,4320,1440,60,0])
        subject=task?["subject"] as? String ?? (string(record,"sourceType")=="local" ? string(record,"subject"):(string(record,"repository") as NSString).lastPathComponent)
        priority=(task?["priority"] as? NSNumber)?.intValue ?? (record["priority"] as? NSNumber)?.intValue ?? 0
        originalTitle = title; originalNotes = notes; dirty = false
    }
    // Explicit re-review preserves user edits but updates the version being reviewed.
    func reviewLatest(){
        guard let latest=latestSource(selected) else {reject("该作业来源已不可用。请保留填写内容，检查课程后重试。");return}
        activeRecord=latest;dateConfirmed=false;dirty=true
        reject("来源已刷新，填写内容已保留。请核对新的原文与截止时间后确认日期。")
    }
    func resolve() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert(); alert.messageText = "保存当前作业的修改？"; alert.informativeText = "保存成功后继续；稍后处理会保留当前填写。"
        alert.addButton(withTitle:"保存并继续"); alert.addButton(withTitle:"放弃修改"); alert.addButton(withTitle:"稍后处理")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveCurrent(advance:false)
        case .alertSecondButtonReturn: dirty = false; return true
        default: return false
        }
    }
    func editDate(_ value:Date){guard floor(value.timeIntervalSince1970/60) != floor(date.timeIntervalSince1970/60) else{return};date=value;hasDate=true;dateConfirmed=true}
    func select(_ record: NSDictionary) { guard !saving,identifier(record) != selected, resolve() else { return };message="";failed=false;load(record) }
    func validation(_ record:NSDictionary, editing:Bool)->String {
        if flag(record,"reviewDeleted"){return "该审核建议已删除，请先恢复。"}
        let kind=string(record,"kind")
        if !kind.isEmpty && kind != "assignment" {return "请先将材料类型确认为作业。"}
        let task=record["existingTask"] as? NSDictionary
        let name=editing ? title : (task?["title"] as? String ?? (string(record,"suggestedTitle").isEmpty ? string(record,"title"):string(record,"suggestedTitle")))
        if name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return "请填写作业名称。"}
        if editing {
            if !hasDate {return "请补全截止日期和时间。"}
            if !dateConfirmed {return "截止时间需要核对；请确认填写的日期和时间。"}
        } else {
            if !(record["warnings"] as? [String] ?? []).isEmpty {return "原文有日期或来源冲突，请逐项核对。"}
            if task?["due"] is Date {return ""}
            if flag(record,"needsTime") {return "缺少截止时间，请补全。"}
            if flag(record,"relative") {
                if suggestion(record)==nil {return "相对日期缺少可靠提交依据，请逐项补全。"}
            } else if flag(record,"needsDate") || !(record["due"] is Date) {return "缺少明确截止日期，请补全。"}
        }
        return ""
    }
    func payload(_ record: NSDictionary, editing: Bool) -> NSDictionary? {
        guard validation(record,editing:editing).isEmpty else{return nil}
        let task=record["existingTask"] as? NSDictionary
        let due=editing ? date : (task?["due"] as? Date ?? (flag(record,"relative") ? suggestion(record) : record["due"] as? Date))
        guard let due else{return nil}
        let proposedTitle=string(record,"suggestedTitle").isEmpty ? string(record,"title"):string(record,"suggestedTitle")
        var draft: [String:Any] = ["title":editing ? title : (task?["title"] as? String ?? proposedTitle),"assignmentDue":due,"dateConfirmed":true]
        if editing {draft["subject"]=subject;draft["priority"]=priority;draft["notes"]=notes;draft["reminderOffsets"]=reminders ? reminderOffsets.sorted(by:>) : [Int]()}
        return ["record":record,"draft":draft] as NSDictionary
    }
    func reject(_ text:String){message=text;failed=true}
    @discardableResult func saveCurrent(advance:Bool) -> Bool {
        guard !saving else{return false}
        guard !paused else{reject(disabledReason);return false}
        guard let record=current else{reject("请先选择一项待审核作业。");return false}
        let reason=validation(record,editing:true)
        guard reason.isEmpty,let payload=payload(record,editing:true) else{reject(reason);return false}
        guard !sourceChanged else{reject("老师原文或识别结果已变化。填写内容已保留，请刷新来源并重新核对。");return false}
        return persist([payload],advance:advance)
    }
    @discardableResult func persist(_ payloads:[NSDictionary],advance:Bool)->Bool {
        guard !saving,!paused else{reject(disabledReason);return false}
        saving=true;failed=false;message="正在校验来源并保存…"
        defer {saving=false}
        let previous=selected
        let result=save?(payloads) ?? "保存接口不可用，请重新打开应用后重试。"
        guard result.isEmpty else{reject(result);return false}
        let savedIDs=Set(payloads.compactMap{($0["record"] as? NSDictionary).map(identifier)})
        checked.subtract(savedIDs);dirty=false;batchPreview=nil
        // Never leave a successfully reviewed item visible if a callback did not refresh.
        records.removeAll{savedIDs.contains(identifier($0))}
        if !advance,let refreshed=records.first(where:{identifier($0)==previous}) {load(refreshed)}
        else if let next=visible.first {load(next)}else{clearDraft()}
        message="已保存 \(payloads.count) 项作业。"
        saving=false
        didSave?()
        return true
    }
    func saveChecked() {
        guard !paused,!saving,resolve() else{return}
        pruneChecks()
        let targets=visible.filter{checked.contains(identifier($0))}
        guard !targets.isEmpty else{reject("请先选择当前列表中的作业。");return}
        batchPreview=targets.map {record in
            let payload=payload(record,editing:false),draft=payload?["draft"] as? NSDictionary
            let task=record["existingTask"] as? NSDictionary
            let basis=record["dateBasis"] as? NSDictionary
            let reference=(basis?["date"] as? Date).map{batchDate($0,zone:string(record,"timeZone"))} ?? ""
            return ReviewBatchItem(id:identifier(record),title:task?["title"] as? String ?? (string(record,"suggestedTitle").isEmpty ? string(record,"title"):string(record,"suggestedTitle")),due:draft?["assignmentDue"] as? Date,course:string(record,"repository"),timeZone:string(record,"timeZone"),basis:reference+" · "+String(string(basis ?? [:],"commit").prefix(7)),reason:validation(record,editing:false),relative:flag(record,"relative"),payload:payload)
        }
        message="请核对批量预览；需补全的条目继续待审核。";failed=false
    }
    @discardableResult func confirmBatch()->Bool {
        guard let preview=batchPreview else{return false}
        let payloads=preview.compactMap(\.payload)
        guard !payloads.isEmpty else{reject("所选条目均需补全，请先逐项处理。" );return false}
        return persist(payloads,advance:true)
    }
}

private struct ReviewDetails: View {
    @ObservedObject var state:ReviewState
    let record:NSDictionary
    private func editing<T>(_ key:ReferenceWritableKeyPath<ReviewState,T>)->Binding<T> {
        Binding(get:{state[keyPath:key]},set:{state[keyPath:key]=$0;state.dirty=true})
    }
    var body:some View {
        Form {
            TaskFields(title:editing(\.title),subject:editing(\.subject),date:Binding(get:{state.date},set:{state.editDate($0)}),notes:editing(\.notes),offsets:Binding(get:{state.reminders ? Array(state.reminderOffsets).sorted(by:>):[]},set:{state.reminders = !$0.isEmpty;state.reminderOffsets=Set($0)}),priority:editing(\.priority),recurrence:.constant([:]),seriesScope:.constant(0),hasDate:state.hasDate && state.dateConfirmed,confirmDate:{state.hasDate=true;state.dateConfirmed=true},recurrenceEnabled:false,dateHint:string(record,"dateText"),notesHeight:120)
            if !((record["warnings"] as? [String] ?? [])+(record["contentWarnings"] as? [String] ?? [])).isEmpty {Section("需核对"){ForEach(Array(((record["warnings"] as? [String] ?? [])+(record["contentWarnings"] as? [String] ?? [])).enumerated()),id:\.offset){Text($0.element).foregroundStyle(.orange)}}}
            Section {WorkspaceDisclosure("老师原文与来源") {
                Text("\(string(record,"repository")) / \(string(record,"path"))").font(.caption).foregroundStyle(.secondary)
                Text(string(record,"snippet")).textSelection(.enabled)
                if let attachments=record["attachments"] as? [NSDictionary] {ForEach(workspaceRows(attachments,key:"path")){Text("附件：\(string($0.record,"path"))\n\(string($0.record,"snippet"))").textSelection(.enabled)}}
                if let basis=record["dateBasis"] as? NSDictionary,let date=basis["date"] as? Date {Text("日期依据：\(date.formatted()) · \(String(string(basis,"commit").prefix(7)))").font(.caption).foregroundStyle(.secondary)}
            }}
        }.formStyle(.grouped).controlSize(.regular).textFieldStyle(.roundedBorder).environment(\.timeZone,TimeZone(identifier:string(record,"timeZone")) ?? .current)
    }
}

private struct ReviewFeedback:View {
    @ObservedObject var state:ReviewState
    var body:some View {
        if !state.message.isEmpty {
            VStack(alignment:.leading,spacing:8) {
                HStack(alignment:.top){Label(state.message,systemImage:state.failed ? "exclamationmark.circle.fill":"checkmark.circle").textSelection(.enabled);Spacer();Button{state.message=""}label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel("关闭提示")}
                if state.sourceChanged {Button("刷新来源，保留填写"){state.reviewLatest()}}
            }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
                .background((state.failed ? Color.red:Color.accentColor).opacity(0.08)).cornerRadius(6)
                .foregroundStyle(state.failed ? Color.red:Color.primary)
                .accessibilityIdentifier("review-feedback")
        }
    }
}
// Native targets are also available to isolated UI tests without global mouse
// input or foreground accessibility. Both editors share this exact save action.
private struct WorkspaceCheck:NSViewRepresentable {
    let title:String
    @Binding var checked:Bool
    var enabled=true
    final class Target:NSObject {
        var change:((Bool)->Void)?
        @objc func press(_ sender:NSButton){change?(sender.state == .on)}
    }
    func makeCoordinator()->Target {Target()}
    func makeNSView(context:Context)->NSButton {
        let button=NSButton(checkboxWithTitle:"",target:context.coordinator,action:#selector(Target.press(_:)))
        button.controlSize = .regular;button.imagePosition = .imageOnly;button.alignment = .center
        button.setContentHuggingPriority(.defaultLow,for:.horizontal)
        return button
    }
    func updateNSView(_ button:NSButton,context:Context){context.coordinator.change={checked=$0};button.state=checked ? .on:.off;button.isEnabled=enabled;button.setAccessibilityLabel(title)}
}
private struct WorkspaceButton:NSViewRepresentable {
    let title:String
    var enabled=true
    var prominent=false
    var identity=""
    var saveShortcut=false
    let action:()->Void
    final class Target:NSObject {
        var action:(()->Void)?
        @objc func press(_ sender:NSButton){guard !isRepeatedWorkspaceEvent(NSApp.currentEvent) else{return};action?()}
    }
    func makeCoordinator()->Target {Target()}
    func makeNSView(context:Context)->NSButton {
        let button=NSButton(title:title,target:context.coordinator,action:#selector(Target.press(_:)))
        button.bezelStyle = .rounded
        #if compiler(>=6.2)
        if #available(macOS 26.0,*) {button.borderShape = .automatic}
        #endif
        button.controlSize = .regular
        button.setContentHuggingPriority(.required,for:.horizontal)
        return button
    }
    func updateNSView(_ button:NSButton,context:Context){
        context.coordinator.action=action;button.title=title;button.isEnabled=enabled
        button.bezelStyle = .rounded
        #if compiler(>=6.2)
        if #available(macOS 26.0,*) {button.bezelStyle = .rounded}
        #endif
        button.bezelColor=prominent ? .controlAccentColor:nil
        button.setAccessibilityIdentifier(identity)
        button.keyEquivalent=saveShortcut ? "\r":"";button.keyEquivalentModifierMask = .command
    }
}
private struct ReviewSaveBar:View {
    @ObservedObject var state:ReviewState
    let advance:Bool
    @ViewBuilder private var status:some View {if !state.disabledReason.isEmpty || state.dirty {Text(state.disabledReason.isEmpty ? "有未保存修改":state.disabledReason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}}
    private var actions:some View {
        HStack {
            if state.saving {ProgressView().progressViewStyle(.linear).frame(width:80)}
            if let record=state.current,!flag(record,"reviewDeleted"),string(record,"reviewStatus") != "已导入" {Button("删除建议",role:.destructive){state.delete(Set([identifier(record)]))}.disabled(state.saving || state.paused)}
            if !state.lastDeleted.isEmpty {Button("撤销删除"){state.restore(state.lastDeleted)}}
            WorkspaceButton(title:advance ? "保存并下一项":(state.current?["existingTask"] == nil ? "确认作业":"保存修改"),enabled:state.disabledReason.isEmpty,prominent:true,identity:"review-save",saveShortcut:true){state.saveCurrent(advance:advance)}.fixedSize().help(state.disabledReason)
        }
    }
    var body:some View {ViewThatFits(in:.horizontal){HStack{status;Spacer();actions};VStack(alignment:.leading,spacing:8){status;HStack{Spacer();actions}}}}
}

private struct ReviewWorkspace: View {
    @ObservedObject var state: ReviewState
    @FocusState private var searchFocused:Bool
    @FocusState private var listFocused:Bool
    private var entries:some View {
        List(selection:Binding<String?>(get:{state.selected.isEmpty ? nil:state.selected},set:{value in
            guard let value,value != state.selected else{return};DispatchQueue.main.async{if let record=state.visible.first(where:{identifier($0)==value}){state.select(record)}}
        })) {
            ForEach(workspaceRows(state.visible)){row in let record=row.record
                HStack(alignment:.top,spacing:8){
                    WorkspaceCheck(title:"选择\(string(record,"title"))",checked:Binding(get:{state.checked.contains(identifier(record))},set:{if $0{state.checked.insert(identifier(record))}else{state.checked.remove(identifier(record))}}),enabled:!state.saving && string(record,"reviewStatus") != "已导入").frame(width:36,height:36)
                    VStack(alignment:.leading,spacing:5){Text(string(record,"suggestedTitle").isEmpty ? string(record,"title"):string(record,"suggestedTitle")).font(.system(size:13,weight:.medium)).lineLimit(2);Text(string(record,"repository")).font(.caption).foregroundStyle(.secondary);Label(flag(record,"reviewDeleted") ? "已删除":(record["existingTask"]==nil ? "新作业":"更新建议"),systemImage:flag(record,"reviewDeleted") ? "trash":(record["existingTask"]==nil ? "tray":"arrow.triangle.2.circlepath")).font(.caption).foregroundStyle(.secondary)}
                }.padding(.vertical,4).tag(identifier(record)).contextMenu {
                    if flag(record,"reviewDeleted"){Button("恢复建议"){state.restore([record])}}
                    else {Button("删除审核建议",role:.destructive){state.delete(Set([identifier(record)]))}}
                }
            }
        }.listStyle(.inset).focused($listFocused)
        .onDeleteCommand {if listFocused,!(NSApp?.keyWindow?.firstResponder is NSText) {state.delete()}}
        .overlay(Button("全选"){state.selectAll()}.keyboardShortcut("a",modifiers:.command).disabled(!listFocused).frame(width:0,height:0).clipped().accessibilityHidden(true))
    }
    private var details:some View {
                Group {
                    if let record=state.current,flag(record,"reviewDeleted") {
                        VStack(alignment:.leading,spacing:12){Text(string(record,"title")).font(.headline);Text(string(record,"snippet")).textSelection(.enabled);Button("恢复审核建议"){state.restore([record])}}.padding(16)
                    } else if let record=state.current {
                        ReviewDetails(state:state,record:record)
                    } else {
                        VStack(spacing:12){Image(systemName:"tray").font(.largeTitle).foregroundStyle(.secondary);Text("暂无待审核作业")}.frame(maxWidth:.infinity,minHeight:240)
                    }
                }.frame(minWidth:300)    }
    var body: some View {
        VStack(spacing:12) {
            VStack(alignment:.leading,spacing:8) {
                HStack{TextField("搜索名称、课程或文件",text:$state.query).textFieldStyle(.roundedBorder).focused($searchFocused)
                Text("已选 \(state.checked.count) / \(state.visible.count) 项").foregroundStyle(.secondary)}
                HStack {
                if state.visible.contains(where:{flag($0,"reviewDeleted")}) {Button("恢复所选"){state.restore(state.visible.filter{state.checked.contains(identifier($0))})}.disabled(state.checked.isEmpty)}
                else {Button("删除所选",role:.destructive){state.delete()}.disabled(state.checked.isEmpty || state.saving)}
                Spacer()
                WorkspaceButton(title:"全选当前结果",enabled:!state.saving && !state.visible.isEmpty,identity:"review-select-all"){state.selectAll()}.fixedSize()
                Button("取消选择"){state.clearChecks()}.disabled(state.checked.isEmpty || state.saving)
                WorkspaceButton(title:"确认所选 \(state.checked.count) 项",enabled:!state.checked.isEmpty && !state.paused && !state.saving && !state.visible.contains{flag($0,"reviewDeleted")},identity:"review-preview-batch"){state.saveChecked()}.fixedSize()
                }
            }
            if state.batchPreview==nil {ReviewFeedback(state:state)}
            if let preview=state.batchPreview {
                ReviewBatchPreview(state:state,items:preview)
            } else {GeometryReader { geometry in
                if geometry.size.width<760 {VSplitView{entries.frame(minHeight:140,idealHeight:180,maxHeight:220);details}}
                else {HSplitView{entries.frame(minWidth:220,idealWidth:280,maxWidth:340);details}}
            }}
            ReviewSaveBar(state:state,advance:true)
        }.padding(12).font(.system(size:13)).tint(Color(nsColor:AMAppearance.accent)).amSecondaryActions().onChange(of:state.searchToken){_ in searchFocused=true}
    }
}

private struct ReviewBatchPreview:View {
    @ObservedObject var state:ReviewState
    let items:[ReviewBatchItem]
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("批量确认预览").font(.title3.bold())
            Text("可确认 \(items.filter{$0.payload != nil}.count) 项 · 需补全 \(items.filter{$0.payload == nil}.count) 项").foregroundStyle(.secondary)
            ReviewFeedback(state:state)
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(items){item in
                        VStack(alignment:.leading,spacing:6) {
                            Label(item.title,systemImage:item.payload == nil ? "exclamationmark.circle":"checkmark.circle")
                            Text(item.course).font(.caption).foregroundStyle(.secondary)
                            if let due=item.due {Text(batchDate(due,zone:item.timeZone));if item.relative {Text("相对日期依据：\(item.basis)，请确认。").foregroundStyle(.orange)}}
                            if !item.reason.isEmpty {Text(item.reason).foregroundStyle(.red)}
                        }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.secondary.opacity(0.06)).cornerRadius(6)
                    }
                }
            }
            HStack{Button("返回审核"){state.batchPreview=nil};Spacer();WorkspaceButton(title:"确认可保存的作业",enabled:!state.paused && !state.saving && items.contains{$0.payload != nil},prominent:true,identity:"review-confirm-batch"){state.confirmBatch()}.fixedSize()}
        }.padding(12)
    }
}

@objc(AMReviewController)
@MainActor public final class AMReviewController: NSViewController {
    private let state=ReviewState()
    @objc public var saveHandler: (([NSDictionary]) -> String)? { get{state.save} set{state.save=newValue} }
    @objc public var decisionHandler:(([NSDictionary],Bool)->String)? {get{state.decision}set{state.decision=newValue}}
    @objc public var sourceHandler: ((String)->NSDictionary?)? {get{state.sourceResolver}set{state.sourceResolver=newValue}}
    @objc public var hasUnsavedChanges: Bool {state.dirty}
    @objc public var editingTaskID:String? {(state.current?["existingTask"] as? NSDictionary)?["id"] as? String}
    @objc public var paused: Bool {get{state.paused}set{state.paused=newValue}}
    @objc public func updateRecords(_ records:[NSDictionary]) {state.refresh(records)}
    @objc public func resolveUnsavedChanges() -> Bool {state.resolve()}
    @objc public func discardChanges() {state.dirty=false;state.refresh(state.records)}
    @objc public func saveCurrent() -> Bool {state.saveCurrent(advance:false)}
    @objc public func focusSearch(){state.searchToken += 1}
    @objc public func selectRecord(withID identifier:String)->Bool { guard let record=state.records.first(where:{string($0,"id")==identifier}) else{return false};state.select(record);return state.selected==identifier }
    public override func loadView() {view=NSHostingView(rootView:ReviewWorkspace(state:state))}
}

@MainActor final class SettingsState: ObservableObject {
    @Published var mode="rules"
    @Published var endpoint="http://localhost:11434"
    @Published var model=""
    @Published var key=""
    @Published var message=""
    @Published var automatic=true
    @Published var autoCompleteSubmittedAssignments=true
    @Published var localAutomatic=true
    @Published var modelDigest=""
    @Published var installedModels:[NSDictionary]=[]
    @Published var localStatus=""
    @Published var localBusy=false
    var localProbe:((NSDictionary,String,@escaping(NSDictionary)->Void)->Void)?
    var lastMode="rules"
    var modeProfiles:[String:(String,String,String)]=[:]
    @Published var cloudCourses:Set<String>=[]
    var availableCourses:[String]=[]
    private var baseline:NSDictionary=[:]
    private var savedValues:NSDictionary {
        var values:[String:Any]=["mode":mode,"automatic":automatic,"autoCompleteSubmittedAssignments":autoCompleteSubmittedAssignments]
        if mode != "rules" {values["endpoint"]=endpoint.trimmingCharacters(in:.whitespacesAndNewlines);values["model"]=model.trimmingCharacters(in:.whitespacesAndNewlines)}
        if mode == "cloud" {values["courses"]=cloudCourses.sorted()}
        if mode == "local" {values["localAutomatic"]=localAutomatic}
        return values as NSDictionary
    }
    var dirty:Bool {get{!key.isEmpty || !savedValues.isEqual(baseline)}set{if !newValue {baseline=savedValues}}}
    var save:((NSDictionary,String)->String)?
    var action:((String)->Void)?
    func apply(_ settings:NSDictionary) {mode=string(settings,"mode");endpoint=string(settings,"endpoint");model=string(settings,"model");automatic=flag(settings,"automaticImport");autoCompleteSubmittedAssignments=settings["autoCompleteSubmittedAssignments"] as? Bool ?? true;localAutomatic=settings["localAutomatic"] as? Bool ?? true;modelDigest=string(settings,"modelDigest");cloudCourses=Set(settings["cloudCourses"] as? [String] ?? []);availableCourses=settings["availableCourses"] as? [String] ?? [];localStatus=string(settings,"localStatus");lastMode=mode;modeProfiles[mode]=(endpoint,model,modelDigest);key="";dirty=false}
    func changeMode(_ value:String) {
        guard lastMode != value else{return};modeProfiles[lastMode]=(endpoint,model,modelDigest)
        if let profile=modeProfiles[value] {endpoint=profile.0;model=profile.1;modelDigest=profile.2}
        else if value=="local" {endpoint="http://localhost:11434";model="";modelDigest=""}
        else if value=="cloud" {endpoint="";model="";modelDigest=""}
        lastMode=value;installedModels=[];localStatus=""
    }
    func probe(_ action:String) {
        guard !localBusy else {return};localBusy=true;localStatus=action=="models" ? "正在检测本地服务…":"正在用模拟作业测试识别…"
        let capturedEndpoint=endpoint, capturedModel=model
        localProbe?(["mode":"local","endpoint":endpoint,"model":model] as NSDictionary,action,{[weak self] result in
            guard let self else{return};self.localBusy=false
            guard self.endpoint==capturedEndpoint, action=="models" || self.model==capturedModel else{return}
            self.localStatus=string(result,"message")
            if let models=result["models"] as? [NSDictionary] {self.installedModels=models;if let selected=models.first(where:{string($0,"name")==self.model}) {let digest=string(selected,"digest");if self.modelDigest != digest {self.modelDigest=digest;self.dirty=true}}}
        })
        if localProbe==nil {localBusy=false;localStatus="本地服务检测接口不可用。"}
    }
    func persist() -> Bool {
        let result=save?(["mode":mode,"endpoint":endpoint,"model":model,"automaticImport":automatic,"autoCompleteSubmittedAssignments":autoCompleteSubmittedAssignments,"localAutomatic":localAutomatic,"modelDigest":modelDigest,"cloudCourses":Array(cloudCourses).sorted()] as NSDictionary,key) ?? "无法保存设置。"
        message=result.isEmpty ? "已保存设置" : result
        if result.isEmpty {key="";dirty=false;DispatchQueue.main.asyncAfter(deadline:.now()+4){[weak self] in if self?.message=="已保存设置" {self?.message=""}}};return result.isEmpty
    }
}
private struct SettingsWorkspace:View {
    @ObservedObject var state:SettingsState
    @TaskValueState<String> private var category="通用"
    private let categories=["通用","作业识别","在线复核","账户与提醒","软件更新","数据与反馈"]
    private func binding<T>(_ key:ReferenceWritableKeyPath<SettingsState,T>)->Binding<T>{Binding(get:{state[keyPath:key]},set:{state[keyPath:key]=$0;state.dirty=true})}
    var body:some View {
        VStack(spacing:0){
            HStack{Text("设置").font(.title2.bold());Spacer();Button("完成"){state.action?("close")}.keyboardShortcut(.cancelAction).accessibilityIdentifier("settings-close")}.padding(16)
            Divider()
            HStack(spacing:0){
                List(selection:$category){ForEach(categories,id:\.self){Text($0).tag($0)}}.listStyle(.sidebar).frame(width:140)
                Divider()
                Form {
                    switch category {
                    case "通用":
                        Section("任务"){Toggle("提交后自动完成作业",isOn:binding(\.autoCompleteSubmittedAssignments))}
                        Section("日历"){Button("设置休息日／工作日…"){state.action?("calendar-overrides")}}
                    case "作业识别":
                        Section("识别方式") {
                            Picker("使用",selection:binding(\.mode)){Text("免费规则").tag("rules");Text("本地模型").tag("local");Text("云端 API").tag("cloud")}
                            Toggle("自动加入日期明确的新作业",isOn:binding(\.automatic))
                            if state.mode=="local" {
                                LabeledContent("服务地址"){TextField("http://localhost:11434",text:binding(\.endpoint))}
                                LabeledContent("模型名称"){TextField("已安装模型名称",text:binding(\.model))}
                                if !state.installedModels.isEmpty {Picker("已安装模型",selection:binding(\.model)){Text("请选择模型").tag("");if !state.model.isEmpty && !state.installedModels.contains(where:{string($0,"name")==state.model}){Text(state.model).tag(state.model)};ForEach(state.installedModels.indices,id:\.self){i in Text(string(state.installedModels[i],"name")).tag(string(state.installedModels[i],"name"))}}.onChange(of:state.model){name in state.modelDigest=state.installedModels.first(where:{string($0,"name")==name}).map{string($0,"digest")} ?? ""}}
                                Toggle("检查时自动使用本地模型",isOn:binding(\.localAutomatic))
                                HStack{Button("检测服务"){state.probe("models")}.disabled(state.localBusy);Button("测试识别"){state.probe("test")}.disabled(state.localBusy || state.model.isEmpty)}
                                if state.localBusy {ProgressView().controlSize(.small)}
                                if !state.localStatus.isEmpty {HStack(alignment:.top){Text(state.localStatus).font(.caption).textSelection(.enabled);Spacer();Button{state.localStatus=""}label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel("关闭检测提示")}}
                            }
                            if state.mode=="cloud" {
                                LabeledContent("服务地址"){TextField("https://服务地址/v1",text:binding(\.endpoint))}
                                LabeledContent("模型名称"){TextField("模型名称",text:binding(\.model))}
                                LabeledContent("API 密钥"){SecureField("留空保留原值",text:binding(\.key))}
                            }
                        }
                        if state.mode=="cloud" {Section("允许发送的课程") {
                            ForEach(state.availableCourses,id:\.self){course in Toggle(course,isOn:Binding(get:{state.cloudCourses.contains(course)},set:{if $0{state.cloudCourses.insert(course)}else{state.cloudCourses.remove(course)}}))}
                            if state.availableCourses.isEmpty {Text("尚未添加课程").foregroundStyle(.secondary)}
                            Text("仅发送确认材料，不发送个人任务或凭据。每天最多20次请求（含失败），可能产生费用。").font(.caption).foregroundStyle(.secondary)
                        }}
                        Section("助手识别") {
                            Button("准备识别材料…"){state.action?("skill-export")}
                            Button("批次与进度…"){state.action?("skill-status")}
                            Button("调整课程…"){state.action?("skill-courses")}
                            Button("重新分析全部…"){state.action?("skill-all")}
                            Button("导入助手结果…"){state.action?("skill-import")}
                        }
                    case "在线复核":Section("作业文件"){Button("配置在线复核…"){state.action?("online-review")}}
                    case "账户与提醒":
                        Section("GitHub"){Button("账户设置…"){state.action?("account")};Button("登录与兼容设置…"){state.action?("advanced")}}
                        Section("提醒"){Button("提醒设置与测试…"){state.action?("notifications")};Button("排查提醒…"){state.action?("notification-help")}}
                    case "软件更新":Section("更新"){Button("检查更新…"){state.action?("check-update")};Button("自动检查设置…"){state.action?("updates")}}
                    default:Section("数据"){Button("恢复任务…"){state.action?("recovery")};Button("诊断与反馈…"){state.action?("diagnostics")}}
                    }
                }.formStyle(.grouped).textFieldStyle(.roundedBorder).controlSize(.regular)
            }
            Divider()
            HStack(alignment:.center){if !state.message.isEmpty {Text(state.message).font(.caption).textSelection(.enabled);Button{state.message=""}label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel("关闭设置提示")};Spacer();Button("保存设置"){_ = state.persist()}.buttonStyle(.borderedProminent).disabled(!state.dirty || state.localBusy).accessibilityIdentifier("settings-save")}.padding(12)
        }.onChange(of:state.mode){state.changeMode($0)}.font(.system(size:13)).tint(Color(nsColor:AMAppearance.accent))
    }
}
@objc(AMSettingsController)
@MainActor public final class AMSettingsController:NSViewController {
    private let state=SettingsState()
    @objc public var localHandler:((NSDictionary,String,@escaping(NSDictionary)->Void)->Void)? {get{state.localProbe}set{state.localProbe=newValue}}
    @objc public var saveHandler:((NSDictionary,String)->String)? {get{state.save}set{state.save=newValue}}
    @objc public var actionHandler:((String)->Void)? {get{state.action}set{state.action=newValue}}
    @objc public var hasUnsavedChanges:Bool {state.dirty}
    @objc public func updateSettings(_ settings:NSDictionary){state.apply(settings)}
    @objc public func resolveUnsavedChanges()->Bool {
        guard state.dirty else{return true};let alert=NSAlert();alert.messageText="保存识别设置？";alert.addButton(withTitle:"保存");alert.addButton(withTitle:"放弃修改");alert.addButton(withTitle:"继续编辑")
        switch alert.runModal(){case .alertFirstButtonReturn:return state.persist();case .alertSecondButtonReturn:state.dirty=false;state.key="";return true;default:return false}
    }
    public override func loadView(){view=NSHostingView(rootView:SettingsWorkspace(state:state))}
}

@MainActor final class CourseState: ObservableObject {
    @Published var summaries:[NSDictionary]=[]
    @Published var showSummary=false
    @Published var records:[NSDictionary]=[]
    @Published var selected:String?
    @Published var information=""
    @Published var empty=""
    @Published var paused=false
    var action:((String,String)->Void)?
    let review=ReviewState()
    private var draftRow:NSDictionary?
    private var refreshedSelection=""
    init() {
        review.didSave = { [weak self] in
            guard let self else { return }
            // The controller refreshes synchronously while the old draft is dirty.
            // Reconcile row selection only after a successful persistence callback.
            if !self.records.contains(where:{identifier($0)==self.selected}) { self.selected=self.records.first(where:{identifier($0)==self.refreshedSelection}).map(identifier) ?? self.records.first.map(identifier) }
            self.draftRow=self.records.first{identifier($0)==self.selected}
            self.review.refresh(self.draftRow.flatMap(self.reviewRecord).map{[$0]} ?? [])
            if let id=self.selected {self.action?("select",id)}
        }
    }
    var current:NSDictionary? {records.first{identifier($0)==selected} ?? (review.dirty ? draftRow:nil)}
    var listSelection:String? {records.contains{identifier($0)==selected} ? selected:nil}
    func reviewRecord(_ record:NSDictionary)->NSDictionary? {
        if let source=record["reviewRecord"] as? NSDictionary {return source}
        if !flag(record,"confirmed") && (string(record,"kind").isEmpty || string(record,"kind")=="assignment") {return record}
        return nil
    }
    @discardableResult func select(_ id:String)->Bool {
        guard let record=records.first(where:{identifier($0)==id}) else{return false}
        if selected == id && draftRow != nil {return true}
        if selected != id && !review.resolve(){return false}
        selected=id;draftRow=record
        if let source=reviewRecord(record) {review.refresh([source])} else {review.refresh([])}
        action?("select",id);return true
    }
    func update(_ records:[NSDictionary], selected:String, information:String, empty:String, paused:Bool) {
        self.records=workspaceRecords(records);self.information=information;self.empty=empty;self.paused=paused;review.paused=paused;refreshedSelection=selected
        // Background refresh retains an unfinished draft. Navigation resolves it first.
        if !review.dirty {self.selected=selected.isEmpty ? nil:selected;draftRow=self.records.first{identifier($0)==self.selected}}
        if let record=current, let source=reviewRecord(record), information.isEmpty {review.refresh([source])}
        else {review.refresh([])}
    }

}
private struct CourseReviewPane:View {
    @ObservedObject var state:ReviewState
    var body:some View {
        if let record=state.current {ReviewDetails(state:state,record:record)}
    }
}
private struct CourseWorkspace:View {
    @ObservedObject var state:CourseState
    @FocusState private var listFocused:Bool
    private func kind(_ record:NSDictionary)->String {flag(record,"confirmed") ? (flag(record,"completed") ? "已完成":"待完成") : string(record,"reviewStatus")=="有更新" ? "有更新，待审核" : ["assignment":"作业","exam":"考试","classroom":"课上任务","unknown":"待确认类型"][string(record,"kind")] ?? "作业"}
    private var entries:some View {
        List(selection:Binding(get:{state.listSelection},set:{if let id=$0, id != state.selected {DispatchQueue.main.async{if state.records.contains(where:{identifier($0)==id}){state.select(id)}}}})) {
            ForEach(workspaceRows(state.records)) { row in
                let record=row.record
                VStack(alignment:.leading,spacing:6) {
                    Text(string(record,"suggestedTitle").isEmpty ? string(record,"title") : string(record,"suggestedTitle")).fontWeight(.medium).lineLimit(2)
                    HStack {Label(kind(record),systemImage:string(record,"kind")=="exam" ? "doc.text" : "checklist");Spacer();if let due=record["due"] as? Date {Text(due,format:.dateTime.month().day().hour().minute())}}
                        .font(.caption).foregroundStyle(.secondary)
                    Text(string(record,"path")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.padding(.vertical,5).tag(identifier(record)).contextMenu {
                    if !flag(record,"confirmed") && string(record,"kind")=="assignment" {Button("删除审核建议",role:.destructive){if state.select(identifier(record)){state.review.delete(Set([identifier(record)]))}}}
                }
            }
        }.listStyle(.inset).frame(minWidth:240).focused($listFocused).onDeleteCommand{if listFocused,!(NSApp?.keyWindow?.firstResponder is NSText),let record=state.current,!flag(record,"confirmed"),string(record,"kind")=="assignment" {state.review.delete()}}
    }
    private var details:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                if !state.information.isEmpty {Text(state.information).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
                else if let record=state.current, !flag(record,"confirmed"), state.reviewRecord(record) != nil {
                    if state.review.dirty && !state.records.contains(where:{identifier($0)==state.selected}) {Text("当前作业不在筛选结果中；未保存的内容保留。").foregroundStyle(.orange)}
                    HStack{Label(kind(record),systemImage:"checklist");Spacer();if !flag(record,"confirmed"){Button("更改类型…"){state.action?("type",identifier(record))}.disabled(state.paused)}}
                    CourseReviewPane(state:state.review)
                } else if let record=state.current {
                    Text(string(record,"suggestedTitle").isEmpty ? string(record,"title") : string(record,"suggestedTitle")).font(.title3.bold())
                    Label(kind(record),systemImage:string(record,"kind")=="exam" ? "doc.text" : "checklist").foregroundStyle(.secondary)
                    if let due=record["due"] as? Date {Text("截止：\(due.formatted(date:.abbreviated,time:.shortened))")}
                    if flag(record,"confirmed") || !string(record,"notes").isEmpty {WorkspaceSection("备注"){VStack(alignment:.leading,spacing:12){Text(string(record,"notes").isEmpty ? "暂无备注":string(record,"notes")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                        if string(record,"notes").isEmpty && !suggestedNotes(record).isEmpty {Button("从识别内容补全…"){state.action?("restore-notes",identifier(record))}.disabled(state.paused)}
                        if flag(record,"confirmed") {Button("编辑任务…"){state.action?("edit-task",identifier(record))}.disabled(state.paused)}
                    }}}
                    if !string(record,"dateText").isEmpty {Text("老师截止原文：\(string(record,"dateText"))").textSelection(.enabled)}
                    if !flag(record,"confirmed") && !string(record,"summary").isEmpty {WorkspaceSection("内容概括"){Text(string(record,"summary")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
                            Text("\(string(record,"repository")) · \(string(record,"path"))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        if !flag(record,"confirmed"){Button("更改类型…"){state.action?("type",identifier(record))}.disabled(state.paused)}
                    }
                    Divider()
                    Text(flag(record,"confirmed") ? "来源信息":"老师原文").font(.headline)
                    ForEach(Array((record["documents"] as? [NSDictionary] ?? [record]).enumerated()),id:\.offset) { _, document in
                        VStack(alignment:.leading,spacing:8){Text(string(document,"path")).font(.caption).foregroundStyle(.secondary);Text(flag(record,"confirmed") ? "原始资料可在课程内容中查看。":(string(document,"snippet").isEmpty ? string(document,"notes"):string(document,"snippet"))).textSelection(.enabled)}
                    }
                } else {VStack(alignment:.leading,spacing:12){Label(state.empty.isEmpty ? "未选择课程内容":state.empty,systemImage:"tray")}}
            }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
        }.frame(minWidth:260)
    }
    private var detailPane:some View {
        VStack(spacing:0){ReviewFeedback(state:state.review).padding(.horizontal,12);details;if let record=state.current,!flag(record,"confirmed"),state.reviewRecord(record) != nil {Divider();ReviewSaveBar(state:state.review,advance:false).padding(12)}}
    }
    private var summaries:some View {
        List{ForEach(workspaceRows(state.summaries)){row in let r=row.record
            HStack(spacing:12){VStack(alignment:.leading,spacing:6){Label(string(r,"name"),systemImage:"books.vertical").fontWeight(.medium);Text("新作业 \((r["newCount"] as? NSNumber)?.intValue ?? 0) · 更新建议 \((r["updateCount"] as? NSNumber)?.intValue ?? 0)").font(.caption);Text(string(r,"status")).font(.caption).foregroundStyle(flag(r,"failed") ? Color.orange:Color.secondary).fixedSize(horizontal:false,vertical:true)};Spacer();WorkspaceButton(title:"\((r["pending"] as? NSNumber)?.intValue ?? 0) 项待审核",enabled:true,prominent:false,identity:"course-summary-"+identifier(r)){DispatchQueue.main.async{state.action?("course-result",identifier(r))}}.fixedSize()}.padding(.vertical,8)
        }}.listStyle(.inset)
    }
    var body:some View {
        GeometryReader { geometry in
            if state.showSummary {summaries}
            else if state.records.isEmpty {detailPane}
            else if geometry.size.width<760 {VSplitView{entries.frame(minHeight:160,idealHeight:220);detailPane.frame(minHeight:180)}}
            else {HSplitView{entries.frame(idealWidth:300,maxWidth:360);detailPane}}
        }.font(.system(size:13)).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent)).amSecondaryActions()
    }
}
@objc(AMCourseController)
@MainActor public final class AMCourseController:NSViewController {
    private let state=CourseState()
    @objc public var actionHandler:((String,String)->Void)? {get{state.action}set{state.action=newValue}}
    @objc public var saveHandler:(([NSDictionary])->String)? {get{state.review.save}set{state.review.save=newValue}}
    @objc public var sourceHandler:((String)->NSDictionary?)? {get{state.review.sourceResolver}set{state.review.sourceResolver=newValue}}
    @objc public var paused:Bool {get{state.review.paused}set{state.review.paused=newValue;state.paused=newValue}}
    @objc public var decisionHandler:(([NSDictionary],Bool)->String)? {get{state.review.decision}set{state.review.decision=newValue}}
    @objc public var hasUnsavedChanges:Bool {state.review.dirty}
    @objc public var editingTaskID:String? {(state.review.current?["existingTask"] as? NSDictionary)?["id"] as? String}
    @objc public func resolveUnsavedChanges()->Bool {state.review.resolve()}
    @objc public func discardChanges(){state.review.dirty=false;state.review.refresh(state.review.records)}
    @objc public func saveCurrent()->Bool {state.review.saveCurrent(advance:false)}
    @objc public func selectRecord(withID id:String)->Bool {state.select(id)}
    @objc public func showCourseSummaries(_ records:[NSDictionary],visible:Bool){state.summaries=workspaceRecords(records);state.showSummary=visible}
    @objc public func updateRecords(_ records:[NSDictionary],selected:String,information:String,empty:String,paused:Bool){state.update(records,selected:selected,information:information,empty:empty,paused:paused)}
    private func scrollViews(_ view:NSView)->[NSScrollView] {var result:[NSScrollView]=[];if let scroll=view as? NSScrollView {result.append(scroll)};for child in view.subviews {result+=scrollViews(child)};return result}
    @objc public func scrollPositions()->[NSValue] {scrollViews(view).map{NSValue(point:$0.contentView.bounds.origin)}}
    @objc public func restoreScrollPositions(_ positions:[NSValue]) {DispatchQueue.main.async {for (scroll,value) in zip(self.scrollViews(self.view),positions){scroll.contentView.scroll(to:value.pointValue);scroll.reflectScrolledClipView(scroll.contentView)}}}
    public override func loadView(){view=NSHostingView(rootView:CourseWorkspace(state:state))}
}

@MainActor
final class SetupState: ObservableObject {
    @Published var records:[NSDictionary]=[]
    @Published var selected:Set<String>=[]
    @Published var paths:[String:String]=[:]
    @Published var query=""
    @Published var step=0
    @Published var busy=false
    @Published var message=""
    @Published var context:NSDictionary=[:]
    var action:((NSDictionary)->Void)?
    var visible:[NSDictionary]{records.filter{query.isEmpty || string($0,"fork").localizedCaseInsensitiveContains(query)}}
    func update(_ records:[NSDictionary],step:Int,busy:Bool,message:String){self.records=workspaceRecords(records);self.step=step;self.busy=busy;self.message=message;for record in self.records {let key=string(record,"fork");if let path=record["path"] as? String {paths[key]=path}}}
    func send(_ action:String,_ course:String=""){self.action?(["action":action,"course":course,"selected":Array(selected),"paths":paths] as NSDictionary)}
}
private struct SetupWorkspace:View {
    @ObservedObject var state:SetupState
    private var official:Bool{string(state.context,"provider").isEmpty || string(state.context,"provider")=="githubCLI"}
    private let steps=["连接账号","选择课程","准备文件","首次检查"]
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            if state.step < 4 {
                HStack(spacing:12){ForEach(0..<4,id:\.self){index in
                    HStack(spacing:5){Image(systemName:index < state.step ? "checkmark.circle.fill":"\(index+1).circle");Text(steps[index]).font(.caption)}.foregroundStyle(index==state.step ? Color(nsColor:AMAppearance.accent):Color.secondary)
                    if index<3 {Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)}
                }}.accessibilityLabel("第 \(state.step+1) 步，共四步")
                Divider()
            }
            WorkspaceHeading(title:state.step < 4 ? (state.step==0 && string(state.context,"code").isEmpty ? "欢迎使用 AM Helper":steps[max(0,min(3,state.step))]):"配置已完成",subtitle:"",symbol:state.step==0 ? "graduationcap":"checklist")
            content
            if state.busy {HStack{ProgressView().progressViewStyle(.linear).frame(width:160);Text(state.step==0 ? "等待 GitHub 登录…":"正在配置课程…").foregroundStyle(.secondary)}}
            Text(state.message).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Divider()
            footer
        }.padding(24).frame(minWidth:620,minHeight:450).font(.system(size:13)).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent)).amSecondaryActions()
    }
    @ViewBuilder private var content:some View {
        if state.step==0 {
            ScrollView {VStack(alignment:.leading,spacing:16){

                WorkspaceDisclosure("登录权限与隐私说明"){Text(official ? "授权页面会显示 GitHub CLI，这是软件内置的 GitHub 官方登录工具。它申请 repo、read:org、gist 权限，范围比所选课程更宽；本应用仅处理你选择的课程，登录令牌只保存在这台 Mac 的钥匙串。":"你在高级设置中选择了旧兼容登录，不使用内置官方工具。旧 OAuth 可能受组织应用限制，旧 GitHub App 需单独安装授权及本机上游凭据。登录令牌只存本机。").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
                Text(official ? "不需要申请批准本项目应用。GitHub 登录、双重验证及学校 SSO 仍由你本人完成，课程访问权限需要已具备。":"如需简化配置，可取消引导，在高级登录设置选择 GitHub 官方登录。").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if !string(state.context,"code").isEmpty {
                    Text(string(state.context,"code")).font(.system(size:30,weight:.semibold,design:.monospaced)).textSelection(.enabled).accessibilityLabel("GitHub 验证码")
                    HStack {Button("复制代码"){state.send("copyCode")};Button("打开 GitHub"){state.send("openLogin")}}
                    Text("等待网页授权…").foregroundStyle(.secondary)
                }
                if !string(state.context,"detail").isEmpty {WorkspaceDisclosure("详情"){Text(string(state.context,"detail")).font(.caption).textSelection(.enabled)}}
            }.frame(maxWidth:.infinity,alignment:.leading)}
        } else if state.step==1 {

            TextField("搜索课程仓库",text:$state.query).textFieldStyle(.roundedBorder).disabled(state.busy)
            if state.records.isEmpty {Text("未找到个人课程 fork。请先在 GitHub fork 课程仓库，再重新读取。").foregroundStyle(.secondary);Button("重新读取课程"){state.send("reload")}.disabled(state.busy)}
            List(workspaceRows(state.visible,key:"fork")){row in
                let record=row.record
                let key=string(record,"fork")
                Toggle(isOn:Binding(get:{state.selected.contains(key)},set:{if $0 {state.selected.insert(key)}else{state.selected.remove(key)}})){
                    VStack(alignment:.leading,spacing:3){Text(key);if flag(record,"existing"){Text("已添加 · 将复用原目录和任务").font(.caption).foregroundStyle(.secondary)}}
                }.toggleStyle(.checkbox)
            }.disabled(state.busy)
        } else if state.step==2 {

            HStack{Button("选择课程总文件夹…"){state.send("find")};Button("下载缺少的课程…"){state.send("download")};Spacer();Button("重试权限检测"){state.send("retry")}}.disabled(state.busy)
            courseRows
        } else if state.step==3 {

            courseRows
        } else {
            Label("课程配置完成",systemImage:"checkmark.circle").font(.headline)
            courseRows
        }
    }
    private var courseRows:some View {
        List(workspaceRows(state.records,key:"fork")){row in
            let record=row.record
            let key=string(record,"fork"),options=record["matches"] as? [String] ?? []
            VStack(alignment:.leading,spacing:6){
                HStack{Image(systemName:flag(record,"ready") ? "checkmark.circle":"exclamationmark.circle");Text(key).fontWeight(.medium);Spacer();if state.step==3 {Button("查看结果"){state.send("result",key)}.disabled(state.busy)};if state.step==2 {Button("选择文件夹…"){state.send("folder",key)}.disabled(flag(record,"invalid") || state.busy)}}
                if !string(record,"upstream").isEmpty {Text("老师："+string(record,"upstream")).font(.caption).foregroundStyle(.secondary)}
                if state.step==2,!options.isEmpty {Picker("已有目录",selection:Binding(get:{state.paths[key] ?? ""},set:{state.paths[key]=$0})){Text("请选择").tag("");ForEach(options,id:\.self){Text($0).tag($0)}}.disabled(state.busy)}
                if state.step==2,let path=state.paths[key],!path.isEmpty {Text(path).font(.caption).textSelection(.enabled).lineLimit(2)}
                if !string(record,"status").isEmpty {Text(string(record,"status")).foregroundStyle(flag(record,"invalid") ? Color.orange:Color.secondary).fixedSize(horizontal:false,vertical:true)}
                if !string(record,"detail").isEmpty {WorkspaceDisclosure("详情"){Text(string(record,"detail")).font(.caption).textSelection(.enabled)}}
                if !string(record,"helpURL").isEmpty,let url=URL(string:string(record,"helpURL")){Link("打开 GitHub 处理…",destination:url)}
            }.padding(.vertical,6)
        }
    }
    private var footer:some View {
        HStack {
            Button(state.busy && state.step==0 ? "取消登录":(state.step==4 ? "稍后查看":"下次继续")){state.send("close")}.keyboardShortcut(.cancelAction)
            if state.step>0 && state.step<4 {Button("返回"){state.send("back")}.disabled(state.busy)}
            Spacer()
            if state.step==0 {if !state.busy && string(state.context,"code").isEmpty{Button("先使用本机作业功能"){state.send("local")}};Button("连接 GitHub 课程"){state.send("login")}.amPrimaryAction().disabled(state.busy || !string(state.context,"code").isEmpty).keyboardShortcut(.defaultAction)}
            else if state.step==1 {Button("下一步：核验课程"){state.send("select")}.amPrimaryAction().disabled(state.busy || state.selected.isEmpty).keyboardShortcut(.defaultAction)}
            else if state.step==2 {Button("确认并开始检查"){state.send("link-check")}.disabled(state.busy || !state.records.contains{!flag($0,"invalid") && !(state.paths[string($0,"fork")] ?? string($0,"path")).isEmpty}).amPrimaryAction().keyboardShortcut(.defaultAction)}
            else if state.step==3 {Button("重试未完成课程"){state.send("retry-check")}.disabled(state.busy);Button("完成配置"){state.send("finish")}.amPrimaryAction().disabled(state.busy).keyboardShortcut(.defaultAction)}
            else {Button("重新运行配置引导"){state.send("restart")}.disabled(state.busy);Button("查看课程"){state.send("courses")}.keyboardShortcut(.defaultAction);Button("查看待审核"){state.send("review")}}
        }
    }
}
@objc(AMSetupController)
@MainActor public final class AMSetupController:NSViewController {
    private let state=SetupState()
    @objc public var actionHandler:((NSDictionary)->Void)?{get{state.action}set{state.action=newValue}}
    @objc public func updateRecords(_ records:[NSDictionary],step:Int,busy:Bool,message:String){state.update(records,step:step,busy:busy,message:message)}
    @objc public func requestCloseSavingDraft(){state.send("close")}
    @objc public func updateContext(_ context:NSDictionary){state.context=context;if let selected=context["selected"] as? [String]{state.selected=Set(selected)}}
    public override func loadView(){view=NSHostingView(rootView:SetupWorkspace(state:state))}
}

@MainActor private final class SkillJobsState:ObservableObject {
    @Published var records=[NSDictionary]()
    @Published var busy=false
    var action:((String,String)->Void)?
}
private struct SkillJobsWorkspace:View {
    @ObservedObject var state:SkillJobsState
    var body:some View {
        VStack(alignment:.leading,spacing:16){

            HStack{Text("助手识别批次").font(.title2.bold());Spacer();Button("清理已完成材料"){state.action?("clean","")}.disabled(state.busy);Button("返回课程"){state.action?("close","")}}

            if state.records.isEmpty {VStack(spacing:12){Image(systemName:"tray").font(.largeTitle);Text("暂无识别批次");Button("准备课程材料"){state.action?("prepare","")}}.frame(maxWidth:.infinity,maxHeight:.infinity)}
            else {List(workspaceRows(state.records,key:"id")){row in
                let record=row.record, key=string(record,"id"), status=string(record,"state")
                VStack(alignment:.leading,spacing:8){
                    HStack{Label(status,systemImage:status=="已接回" ? "checkmark.circle":(status=="需处理" ? "exclamationmark.triangle":"clock"));Spacer();if let date=record["date"] as? Date {Text(date,style:.date).foregroundStyle(.secondary)}}
                    Text("\((record["count"] as? NSNumber)?.intValue ?? 0) 份文档 · \((record["courses"] as? [String] ?? []).map{String($0.split(separator:"/").last ?? "")}.joined(separator:"、"))").font(.caption).foregroundStyle(.secondary)
                    if !string(record,"message").isEmpty {Text(string(record,"message")).textSelection(.enabled)}
                    if flag(record,"cleaned"){Text("材料已清理；识别进度仍保留").font(.caption).foregroundStyle(.secondary)}
                    HStack{if !flag(record,"cleaned"){Button("复制指令"){state.action?("copy",key)};Button("显示材料"){state.action?("reveal",key)};if !string(record,"reportVersion").isEmpty {Button("查看检查报告"){state.action?("view-report",key)}}};if status=="需处理" {Button("重试接回"){state.action?("retry",key)};if string(record,"reportVersion").isEmpty {Button("重新准备未成功材料"){state.action?("prepare-failed",key)}}}}.disabled(state.busy)
                }.padding(.vertical,8)
            }.listStyle(.inset)}
        }.padding(16).font(.system(size:13)).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent)).amSecondaryActions()
    }
}
@objc(AMSkillJobsController) @MainActor public final class AMSkillJobsController:NSViewController {
    private let state=SkillJobsState()
    @objc public var actionHandler:((String,String)->Void)? {get{state.action}set{state.action=newValue}}
    @objc public func updateRecords(_ records:[NSDictionary],busy:Bool){state.records=records;state.busy=busy}
    public override func loadView(){view=NSHostingView(rootView:SkillJobsWorkspace(state:state))}
}

@MainActor private final class PlanningState:ObservableObject {
    @Published var task:NSDictionary=[:]
    @Published var sections:[NSDictionary]=[]
    @Published var notice=""
    var action:((String,String,String,String)->Void)?
}
private struct TaskPlanningView:View {
    @ObservedObject var state:PlanningState
    private var children:[NSDictionary] {state.task["subtasks"] as? [NSDictionary] ?? []}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{Label("计划完成",systemImage:"calendar").font(.system(size:13,weight:.semibold));Spacer();WorkspaceButton(title:string(state.task,"plannedDate").isEmpty ? "安排到…":string(state.task,"plannedDate"),identity:"task-plan"){state.action?("plan",identifier(state.task),"","")}.fixedSize()}

            Divider()
            HStack{Text("子任务").font(.system(size:13,weight:.semibold));Spacer();Text("\(children.filter{flag($0,"completed")}.count)/\(children.count)").foregroundStyle(.secondary);WorkspaceButton(title:"添加…",identity:"subtask-add"){state.action?("add",identifier(state.task),"","")}.fixedSize().help("添加子任务")}
            if children.isEmpty{Text("暂无子任务").font(.caption).foregroundStyle(.secondary)}
            ForEach(workspaceRows(children)){row in
                HStack(alignment:.top,spacing:8){
                    Toggle("",isOn:Binding(get:{flag(row.record,"completed")},set:{_ in state.action?("toggle",identifier(state.task),identifier(row.record),"")})).labelsHidden().toggleStyle(.checkbox).accessibilityLabel((flag(row.record,"completed") ? "已完成：":"未完成：")+string(row.record,"title")).accessibilityHint("切换子任务完成状态")
                    VStack(alignment:.leading,spacing:3){Text(string(row.record,"title")).strikethrough(flag(row.record,"completed")).lineLimit(3).help(string(row.record,"title")).fixedSize(horizontal:false,vertical:true);if !string(row.record,"plannedDate").isEmpty{Text(string(row.record,"plannedDate")).font(.caption).foregroundStyle(.secondary)}}.frame(maxWidth:.infinity,alignment:.leading)
                    Menu{Button("编辑名称…"){state.action?("edit",identifier(state.task),identifier(row.record),"")};Button("安排到…"){state.action?("plan",identifier(state.task),identifier(row.record),"")};Button("上移"){state.action?("up",identifier(state.task),identifier(row.record),"")};Button("下移"){state.action?("down",identifier(state.task),identifier(row.record),"")};Divider();Button("删除",role:.destructive){state.action?("delete",identifier(state.task),identifier(row.record),"")}}label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).frame(width:24).help("子任务操作")
                }.padding(.vertical,3)
            }
            if !children.isEmpty && children.allSatisfy({flag($0,"completed")}) && !flag(state.task,"completed"){Label("所有子任务已完成",systemImage:"checkmark.circle").font(.caption).foregroundStyle(.secondary)}
        }.padding(12).font(.system(size:13)).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color(nsColor:AMAppearance.surface))
    }
}
@objc(AMTaskPlanningController) public final class AMTaskPlanningController:NSViewController {
    private let state=PlanningState()
    @objc public var actionHandler:((String,String,String,String)->Void)? {didSet{state.action=actionHandler}}
    public override func loadView(){view=NSHostingView(rootView:TaskPlanningView(state:state))}
    @objc public func updateTask(_ task:NSDictionary){state.task=workspaceSnapshot(task) as! NSDictionary}
}
private struct WeeklyPlanningView:View {
    @ObservedObject var state:PlanningState
    private func invoke(_ action:String,_ row:NSDictionary,_ date:String=""){state.action?(action,string(row,"taskID"),string(row,"subtaskID"),date)}
    private func item(_ row:NSDictionary)->some View {
        Button{invoke("select",row)}label:{
            VStack(alignment:.leading,spacing:5){Text(string(row,"title")).font(.system(size:13,weight:.medium)).lineLimit(3).frame(maxWidth:.infinity,alignment:.leading)
                if !string(row,"parentTitle").isEmpty{Label(string(row,"parentTitle"),systemImage:"checklist").font(.caption).lineLimit(2).foregroundStyle(.secondary)}
                if let due=row["due"] as? Date{Text("截止 "+due.formatted(.dateTime.month().day().hour().minute())).font(.caption2).foregroundStyle(.secondary)}
            }.padding(10).background(Color(nsColor:AMAppearance.surface)).clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Color(nsColor:AMAppearance.separator).opacity(0.5),lineWidth:0.5))
        }.buttonStyle(.plain).accessibilityLabel(string(row,"title")+"，查看作业详情")
        .contextMenu{Button("安排到…"){invoke("plan",row)};Button("取消安排"){invoke("set-plan",row,"")}}
        .onDrag{let payload=["task":string(row,"taskID"),"subtask":string(row,"subtaskID")];let data=(try? JSONSerialization.data(withJSONObject:payload)) ?? Data();return NSItemProvider(object:(String(data:data,encoding:.utf8) ?? "") as NSString)}
    }
    private func section(_ section:NSDictionary)->some View {
        let rows=section["items"] as? [NSDictionary] ?? []
        let parents=rows.filter{string($0,"subtaskID").isEmpty}.count
        let day=section["dayInfo"] as? NSDictionary
        return VStack(alignment:.leading,spacing:8){Text(string(section,"label")).font(.system(size:13,weight:.semibold));if let day{Text(string(day,"name")+(flag(day,"known") ? "":" · 假期未收录")).font(.caption2).foregroundStyle(.secondary).help(string(day,"source"))};Text("\(parents) 项作业 · \(rows.count-parents) 个步骤").font(.caption2).foregroundStyle(.secondary)
            LazyVStack(spacing:8){ForEach(workspaceRows(rows)){row in item(row.record)};if rows.isEmpty{Text("暂无安排").font(.caption).foregroundStyle(.secondary).padding(.vertical,16).frame(maxWidth:.infinity)}}
        }.padding(10).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color(nsColor:AMAppearance.sidebar).opacity(0.55)).clipShape(RoundedRectangle(cornerRadius:6))
        .onDrop(of:["public.utf8-plain-text"],isTargeted:nil){providers in
            guard let provider=providers.first,provider.canLoadObject(ofClass:NSString.self) else{return false}
            let sectionID=identifier(section);guard sectionID != "overdue" else{return false}
            provider.loadObject(ofClass:NSString.self){object,_ in
                guard let text=object as? String,text.utf8.count<4096,let data=text.data(using:.utf8),let payload=(try? JSONSerialization.jsonObject(with:data)) as? [String:String],let task=payload["task"],let sub=payload["subtask"] else{return}
                DispatchQueue.main.async{state.action?("set-plan",task,sub,sectionID == "unplanned" ? "":sectionID)}
            };return true
        }
    }
    var body:some View {
        GeometryReader{geometry in
            VStack(alignment:.leading,spacing:12){
                HStack{Button{state.action?("previous","","","")}label:{Image(systemName:"chevron.left")}.help("上一周").accessibilityLabel("上一周");Button("本周"){state.action?("current","","","")}.accessibilityIdentifier("week-current");Button{state.action?("next","","","")}label:{Image(systemName:"chevron.right")}.help("下一周").accessibilityLabel("下一周");Spacer();Text(state.sections.first?["date"] as? Date ?? Date(),format:.dateTime.year().month().day()).font(.headline)}

                if !state.notice.isEmpty{Text(state.notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}
                ScrollView{
                    if geometry.size.width>=1000{HStack(alignment:.top,spacing:8){ForEach(workspaceRows(Array(state.sections.prefix(7)))){row in section(row.record)}}}
                    else{LazyVStack(spacing:12){ForEach(workspaceRows(Array(state.sections.prefix(7)))){row in section(row.record)}}}
                    ForEach(workspaceRows(Array(state.sections.dropFirst(7)))){row in section(row.record).padding(.top,12)}
                }
            }.padding(4)
        }.background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent)).amSecondaryActions()
    }
}
@objc(AMWeeklyPlanningController) public final class AMWeeklyPlanningController:NSViewController {
    private let state=PlanningState()
    @objc public var actionHandler:((String,String,String,String)->Void)? {didSet{state.action=actionHandler}}
    public override func loadView(){view=NSHostingView(rootView:WeeklyPlanningView(state:state))}
    @objc public func updateSections(_ sections:[NSDictionary],notice:String){state.sections=workspaceRecords(sections);state.notice=notice}
}

@MainActor private final class SubmissionHistoryState:ObservableObject {
    @Published var reading=false
    @Published var records:[NSDictionary]=[]
    @Published var selected:String?
    @Published var busy=false
    var action:((String,String)->Void)?
}
private struct SubmissionHistoryView:View {
    @ObservedObject var state:SubmissionHistoryState
    private var current:NSDictionary? {state.records.first{recordIdentifier($0)==state.selected}}
    private func details(_ r:NSDictionary)->some View {
        ScrollView{VStack(alignment:.leading,spacing:16){
            Text(string(r,"label")).font(.headline)
            Text("\(string(r,"repository")) · \(string(r,"branch"))").foregroundStyle(.secondary)
            Text(string(r,"origin")=="external" ? (string(r,"kind")=="merge" ? "外部 Git 合并":((r["taskIDs"] as? [String] ?? []).isEmpty ? "外部 Git 提交":"外部 Git 提交 · 已关联")):(string(r,"kind")=="submission" || string(r,"kind")=="existing" ? "作业提交":"课程同步／合并")).font(.caption)
            if string(r,"origin")=="external" && !flag(r,"teacherHistoryKnown"){Text("上游历史尚未完整核对；此记录暂未判断是否为作业。").font(.caption).foregroundStyle(.secondary)}
            Text(string(r,"message")).textSelection(.enabled)
            if !string(r,"commit").isEmpty{WorkspaceSection("提交版本"){Text(string(r,"commit")).font(.system(.caption,design:.monospaced)).textSelection(.enabled);Button("在 GitHub 查看"){state.action?("open",identifier(r))}}}
            WorkspaceSection("操作与核验"){Text("本机操作：\((r["date"] as? Date ?? Date()).formatted())");if let checked=r["checkedAt"] as? Date{Text("最近核验：\(checked.formatted())")};if let confirmed=r["confirmedAt"] as? Date{Text("曾确认推送：\(confirmed.formatted())")}}
            if let review=r["review"] as? NSDictionary {WorkspaceSection("提交前检查"){Text("\((review["date"] as? Date ?? Date()).formatted()) · \((review["count"] as? NSNumber)?.intValue ?? 0) 条建议");Text(string(review,"coverage")=="local" ? "本机检查，用户确认继续":(string(review,"coverage")=="partial" ? "含助手复核；部分未完成，用户确认继续":"含助手复核，用户确认继续")).foregroundStyle(.secondary)}}
            if string(r,"completionStatus")=="completed" {Label("已处理关联作业",systemImage:"checkmark.circle").foregroundStyle(.secondary)}
            else if string(r,"completionStatus")=="waiting" {Text("待关联作业").foregroundStyle(.secondary)}
            else if string(r,"completionStatus")=="deferred" {Text("编辑结束后完成作业").foregroundStyle(.secondary)}
            WorkspaceSection("实际文件"){ForEach(r["files"] as? [String] ?? [],id:\.self){Text($0).font(.caption).textSelection(.enabled)}}
            HStack{Button("关联作业…"){state.action?("associate",identifier(r))};Button("重新核验"){state.action?("verify",identifier(r))};if string(r,"origin") != "external" && string(r,"state") != "confirmed" && !string(r,"commit").isEmpty{Button("核验并重试推送"){state.action?("retry",identifier(r))}}}.disabled(state.busy)
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading)}
    }
    var body:some View {GeometryReader{geo in
        let list=List(selection:Binding(get:{state.selected},set:{state.selected=$0})){ForEach(workspaceRows(state.records)){row in let r=row.record;VStack(alignment:.leading,spacing:5){Text(string(r,"message").isEmpty ? "课程操作":string(r,"message")).lineLimit(2);Text(string(r,"label")).font(.caption).foregroundStyle(string(r,"state")=="confirmed" ? Color.secondary:Color.orange);Text(String(string(r,"commit").prefix(12))).font(.caption2.monospaced())}.padding(.vertical,4).tag(identifier(r))}}.listStyle(.inset)
        VStack(alignment:.leading,spacing:8){HStack{Text("提交记录").font(.headline);Spacer();Button("刷新终端提交"){state.action?("refresh-external","")}.disabled(state.busy);Button("更早记录"){state.action?("more-external","")}.disabled(state.busy);Button("关联已有提交…"){state.action?("existing","")}.disabled(state.busy)}.padding(.horizontal,12)
            if state.reading{HStack{ProgressView().progressViewStyle(.linear).frame(width:140);Text("正在读取／核验终端提交…").foregroundStyle(.secondary)}.padding(.horizontal,12)}
            if state.records.isEmpty{VStack(spacing:12){Image(systemName:"clock.arrow.circlepath").font(.largeTitle);Text("暂无提交记录").font(.headline)}.frame(maxWidth:.infinity,maxHeight:.infinity)}
            else if geo.size.width<760{VStack(spacing:0){list.frame(height:max(150,geo.size.height*0.4));Divider();if let r=current{details(r)}else{Text("未选择提交记录").foregroundStyle(.secondary).padding()}}}
            else{HStack(spacing:0){list.frame(width:280);Divider();if let r=current{details(r)}else{Text("未选择提交记录").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)}}}
        }.background(Color(nsColor:AMAppearance.canvas))
    }}
}
@objc(AMSubmissionHistoryController) @MainActor public final class AMSubmissionHistoryController:NSViewController {
    private let state=SubmissionHistoryState()
    @objc public var actionHandler:((String,String)->Void)? {didSet{state.action=actionHandler}}
    @objc public func updateReading(_ reading:Bool){state.reading=reading}
    @objc public func updateRecords(_ records:[NSDictionary],busy:Bool){state.records=workspaceRecords(records);state.busy=busy;if !state.records.contains(where:{recordIdentifier($0)==state.selected}){state.selected=state.records.first.map{recordIdentifier($0)}}}
    public override func loadView(){view=NSHostingView(rootView:SubmissionHistoryView(state:state))}
}

private struct CaptureTextEditor:NSViewRepresentable {
    @Binding var text:String
    final class Coordinator:NSObject,NSTextViewDelegate {
        var binding:Binding<String>
        init(_ binding:Binding<String>){self.binding=binding}
        func textDidChange(_ notification:Notification){if let view=notification.object as? NSTextView{binding.wrappedValue=view.string}}
    }
    func makeCoordinator()->Coordinator{Coordinator($text)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .noBorder
        let view=NSTextView(frame:.zero);view.isRichText=false;view.allowsUndo=true;view.font = .systemFont(ofSize:13);view.textContainerInset=NSSize(width:8,height:8);view.textColor = .textColor;view.backgroundColor = .textBackgroundColor
        view.isVerticallyResizable=true;view.isHorizontallyResizable=false;view.autoresizingMask = [.width];view.textContainer?.widthTracksTextView=true;view.delegate=context.coordinator;view.setAccessibilityIdentifier("quick-input");view.setAccessibilityLabel("作业通知原文");scroll.documentView=view;return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context){context.coordinator.binding=$text;if let view=scroll.documentView as? NSTextView,view.string != text{view.string=text}}
}

@MainActor final class QuickEntryState:ObservableObject {
    @Published var text=""
    @Published var entries:[NSDictionary]=[]
    @Published var selected:String?
    @Published var notice=""
    private var lastNotice=""
    private var dismissedNotice=""
    func presentNotice(_ text:String){if text != lastNotice {dismissedNotice=""};lastNotice=text;notice=dismissedNotice==text ? "":text}
    func dismissNotice(){dismissedNotice=lastNotice;notice=""}
    @Published var busy=false
    @Published var showingOriginal=false
    @Published var imageScale=1.0
    @Published var ocrImage:NSImage?
    @Published var ocrWarnings=""
    @Published var parsedText=""
    @Published var explicitReference=false
    @Published var reference=Date()
    var courses:[NSDictionary]=[]
    var action:((String,NSDictionary)->Void)?
    var current:NSDictionary? {entries.first{identifier($0)==selected}}
    var snapshot:NSDictionary {["text":text,"entries":entries,"referenceDate":reference,"explicitReference":explicitReference]}
    func send(_ name:String){action?(name,snapshot)}
    func change(_ key:String,_ value:Any){guard let id=selected,let index=entries.firstIndex(where:{identifier($0)==id})else{return};let copy=entries[index].mutableCopy() as! NSMutableDictionary;if NSDictionary(dictionary:["value":copy[key] ?? NSNull()]).isEqual(to:["value":value]){return};copy[key]=value;if key != "selected"{copy["edited"]=true;var fields=Set(copy["editedFields"] as? [String] ?? []);fields.insert(key);copy["editedFields"]=Array(fields)};entries[index]=copy.copy() as! NSDictionary;send("draft")}
    func field(_ key:String)->Binding<String>{Binding(get:{self.current.map{string($0,key)} ?? ""},set:{self.change(key,$0)})}
    private func dateFormatter(_ format:String)->DateFormatter {let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat=format;formatter.isLenient=false;formatter.timeZone=TimeZone(identifier:current.map{string($0,"timeZone")} ?? "") ?? .current;return formatter}
    var knownDate:Date? {guard let current else{return nil};let text=string(current,"dateText");guard text.range(of:"^\\d{4}-\\d{1,2}-\\d{1,2} [0-9]{1,2}:[0-9]{2}$",options:.regularExpression) != nil else{return nil};return dateFormatter("yyyy-MM-dd HH:mm").date(from:text)}
    var displayDate:Date {if let knownDate{return knownDate};if let current,let day=dateFormatter("yyyy-MM-dd").date(from:string(current,"dateText")){var calendar=Calendar(identifier:.gregorian);calendar.timeZone=dateFormatter("yyyy-MM-dd").timeZone;return calendar.date(bySettingHour:23,minute:59,second:0,of:day) ?? day};return Date(timeIntervalSince1970:floor(reference.timeIntervalSince1970/60)*60)}
    var dateBinding:Binding<Date> {Binding(get:{self.displayDate},set:{if $0 != self.displayDate{self.confirmDate($0)}})}
    func confirmDate(_ date:Date?=nil){change("dateText",dateFormatter("yyyy-MM-dd HH:mm").string(from:date ?? displayDate))}
}
private struct QuickEntryView:View {
    @ObservedObject var state:QuickEntryState
    private var rows:some View {
        List(selection:Binding(get:{state.selected},set:{state.selected=$0})){ForEach(workspaceRows(state.entries)){row in let r=row.record
            HStack(alignment:.top){Toggle("",isOn:Binding(get:{flag(r,"selected")},set:{new in state.selected=identifier(r);state.change("selected",new)})).labelsHidden().accessibilityLabel("选择 \(string(r,"title"))");VStack(alignment:.leading,spacing:5){Text(string(r,"title").isEmpty ? "待填写名称":string(r,"title")).lineLimit(2);Text(string(r,"dateText").isEmpty ? "待补全截止时间":string(r,"dateText")).font(.caption).foregroundStyle(.secondary)}}.padding(.vertical,4).tag(identifier(r))
        }}.listStyle(.inset).onCommand(#selector(NSText.selectAll(_:))){for index in state.entries.indices{let copy=state.entries[index].mutableCopy() as! NSMutableDictionary;copy["selected"]=true;state.entries[index]=copy};state.send("draft")}
    }
    private var details:some View {
        Form {if let r=state.current {
            TaskFields(title:state.field("title"),subject:state.field("subject"),date:state.dateBinding,notes:state.field("notes"),offsets:Binding(get:{(state.current?["reminderOffsets"] as? [NSNumber] ?? []).map(\.intValue)},set:{state.change("reminderOffsets",$0)}),priority:Binding(get:{(state.current?["priority"] as? NSNumber)?.intValue ?? 0},set:{state.change("priority",$0)}),recurrence:.constant([:]),seriesScope:.constant(0),hasDate:state.knownDate != nil,confirmDate:{state.confirmDate()},recurrenceEnabled:false,dateHint:string(r,"hint"))
            if !state.courses.isEmpty {Section {Menu("关联课程"){Button("不关联"){state.change("courseRepository","")};ForEach(workspaceRows(state.courses)){row in Button(string(row.record,"name")){state.change("courseRepository",identifier(row.record));state.change("subject",string(row.record,"name"))}}}}}
            Section {WorkspaceDisclosure("老师原文与来源"){Text(string(r,"evidence")).textSelection(.enabled)}}
        }else{Text("未选择作业").foregroundStyle(.secondary)}}.formStyle(.grouped).controlSize(.regular).textFieldStyle(.roundedBorder).environment(\.timeZone,TimeZone(identifier:state.current.map{string($0,"timeZone")} ?? "") ?? .current)
    }
    var body:some View {GeometryReader{geo in VStack(alignment:.leading,spacing:12){
        HStack{Text("从文字或截图录入").font(.title2.bold());Spacer();Button("保存草稿并关闭"){state.send("close")}.keyboardShortcut(.cancelAction)}

        HStack(alignment:.top,spacing:8){CaptureTextEditor(text:$state.text).frame(height:state.ocrImage == nil ? 90:150).overlay(RoundedRectangle(cornerRadius:6).stroke(Color(nsColor:.separatorColor)));if let image=state.ocrImage{VStack(alignment:.leading,spacing:4){Image(nsImage:image).resizable().scaledToFit().frame(maxHeight:100).accessibilityLabel("录入截图原图");ScrollView{Text(state.ocrWarnings).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}.frame(height:40);HStack{Button("放大原图…"){state.showingOriginal=true};Button("关闭"){state.ocrImage=nil}.accessibilityLabel("关闭截图对照")}}.frame(width:min(260,geo.size.width * 0.36))}}.onChange(of:state.text){_ in state.send("draft")}.task(id:state.text){let value=state.text;try? await Task.sleep(nanoseconds:450_000_000);if !Task.isCancelled && !state.busy && !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && state.parsedText != value{state.send("source-changed")}}
        HStack{Button("粘贴"){state.send("paste")};Button("选择截图…"){state.send("image")};WorkspaceButton(title:"重新识别",enabled:!state.busy,prominent:false,identity:"quick-parse"){state.send("parse")}.fixedSize();Button("助手识别…"){state.send("skill")};Spacer();if state.busy{ProgressView().progressViewStyle(.linear).frame(width:160)}}
        HStack{Toggle("指定消息日期",isOn:$state.explicitReference).onChange(of:state.explicitReference){_ in state.send("draft")};if state.explicitReference{DatePicker("",selection:$state.reference).labelsHidden().onChange(of:state.reference){_ in state.send("draft")}};Spacer()}
        HStack{Button("全选"){for i in state.entries.indices{let copy=state.entries[i].mutableCopy() as! NSMutableDictionary;copy["selected"]=true;state.entries[i]=copy};state.send("draft")};Button("取消选择"){for i in state.entries.indices{let copy=state.entries[i].mutableCopy() as! NSMutableDictionary;copy["selected"]=false;state.entries[i]=copy};state.send("draft")};Text("已选 \(state.entries.filter{flag($0,"selected")}.count) / \(state.entries.count)").foregroundStyle(.secondary);Spacer()}
        if geo.size.width<760{VStack(spacing:0){rows.frame(height:150);Divider();details}}else{HStack(spacing:0){rows.frame(width:260);Divider();details}}
        if !state.notice.isEmpty {HStack(alignment:.top){Text(state.notice).font(.callout).textSelection(.enabled).accessibilityIdentifier("quick-status");Spacer();Button{state.dismissNotice()}label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel("关闭提示")}}
        HStack{Button("手动导入助手结果…"){state.send("import")};Spacer();WorkspaceButton(title:"保存选中作业",enabled:!state.busy && state.entries.contains{flag($0,"selected")},prominent:true,identity:"quick-save",saveShortcut:true){state.send("save")}.fixedSize()}
    }.padding(16).font(.system(size:13)).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent)).amSecondaryActions().accessibilityElement(children:.contain)
    .sheet(isPresented:$state.showingOriginal){VStack(spacing:12){HStack{Text("截图原图").font(.headline);Spacer();Text("缩放");Slider(value:$state.imageScale,in:0.25...3).frame(width:140).accessibilityLabel("原图缩放");Button("完成"){state.showingOriginal=false}.keyboardShortcut(.cancelAction)};if let image=state.ocrImage{ScrollView([.horizontal,.vertical]){Image(nsImage:image).resizable().frame(width:image.size.width*state.imageScale,height:image.size.height*state.imageScale).accessibilityLabel("完整录入截图，可滚动查看")}}}.padding(16).frame(minWidth:620,idealWidth:800,minHeight:460,idealHeight:600)}}}
}
@objc(AMQuickEntryController) @MainActor public final class AMQuickEntryController:NSViewController {
    private let state=QuickEntryState()
    @objc public var actionHandler:((String,NSDictionary)->Void)? {didSet{state.action=actionHandler}}
    @objc public var snapshot:NSDictionary {state.snapshot}
    @objc public func updateDraft(_ draft:NSDictionary,courses:[NSDictionary],notice:String,busy:Bool){state.parsedText=(draft["material"] as? NSDictionary).map{string($0,"text")} ?? "";state.text=string(draft,"text");state.entries=workspaceRecords(draft["entries"] as? [NSDictionary] ?? []);state.reference=draft["referenceDate"] as? Date ?? Date();state.explicitReference=flag(draft,"explicitReference");state.courses=workspaceRecords(courses);state.presentNotice(notice);state.busy=busy;if !state.entries.contains(where:{recordIdentifier($0)==state.selected}){state.selected=state.entries.first.map{recordIdentifier($0)}}}
    @objc public func setNotice(_ notice:String,busy:Bool){state.presentNotice(notice);state.busy=busy}
    @objc public func setOCRPreview(_ image:NSImage,warnings:String){state.ocrImage=image;state.ocrWarnings=warnings}
    public override func loadView(){view=NSHostingView(rootView:QuickEntryView(state:state))}
}

private func recordIdentifier(_ record:NSDictionary)->String {identifier(record)}

// The same preview is used for folders and an explicit file selection. It never
// changes submission selection, Git state or the associated task.
private final class CheckScopeState:ObservableObject {
    @Published var records:[NSDictionary]=[]
    @Published var selected=Set<String>()
    @Published var query=""
    @Published var chosen=""
    @Published var busy=true
    @Published var notice="正在整理文件夹…"
    @Published var preview:NSView?
    var initialized=false
    var initialSelection=Set<String>()
    var action:((NSDictionary)->Void)?
    var visible:[NSDictionary]{records.filter{query.isEmpty || string($0,"path").localizedCaseInsensitiveContains(query)}}
    var valid:[NSDictionary]{records.filter{flag($0,"selectable") && selected.contains(string($0,"path"))}}
    var bytes:Int64{valid.reduce(0){$0 + (($1["bytes"] as? NSNumber)?.int64Value ?? 0)}}
    var canStart:Bool{!busy && !valid.isEmpty && valid.count<=256 && bytes<=64*1024*1024}
    var hint:String{valid.count>256 ? "最多256个文件，请减少选择。":(bytes>64*1024*1024 ? "超过64 MB，请缩小范围。":(valid.isEmpty ? "请选择至少一个文件。":"只读检查当前文件，不提交或推送。"))}
    func send(_ action:String){self.action?(["action":action,"paths":valid.map{string($0,"path")},"selected":chosen] as NSDictionary)}
}
private final class CheckFileNode:Identifiable {
    let id:String
    var record:NSDictionary?
    var children:[CheckFileNode]?
    init(_ id:String,record:NSDictionary?=nil){self.id=id;self.record=record}
}
private func checkFileTree(_ records:[NSDictionary],flat:Bool)->[CheckFileNode]{
    if flat{return records.map{CheckFileNode(string($0,"path"),record:$0)}}
    let root=CheckFileNode("");root.children=[]
    for row in records.sorted(by:{string($0,"path").localizedStandardCompare(string($1,"path")) == .orderedAscending}) {
        var parent=root;var path=""
        let components=string(row,"path").split(separator:"/").map(String.init)
        for (index,part) in components.enumerated(){path=path.isEmpty ? part:path+"/"+part
            if let child=parent.children?.first(where:{$0.id==path}){parent=child;continue}
            let child=CheckFileNode(path,record:index==components.count-1 ? row:nil)
            if child.record==nil{child.children=[]};if parent.children==nil{parent.children=[]};parent.children?.append(child);parent=child
        }
    };return root.children ?? []
}
private struct CheckPreviewHost:NSViewRepresentable {
    let preview:NSView?
    func makeNSView(context:Context)->NSView{NSView()}
    func updateNSView(_ view:NSView,context:Context){guard let preview=preview else{return};if preview.superview !== view{view.subviews.forEach{$0.removeFromSuperview()};preview.frame=view.bounds;preview.autoresizingMask=[.width,.height];view.addSubview(preview)}}
}
private final class CheckSplitAnchorView:NSView {
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();DispatchQueue.main.async{[weak self] in var parent=self?.superview;while let view=parent{if let split=view as? NSSplitView{split.autosaveName="AMFileCheckScopeSplit";break};parent=view.superview}}}
}
private struct CheckSplitAnchor:NSViewRepresentable {
    func makeNSView(context:Context)->NSView{CheckSplitAnchorView()}
    func updateNSView(_ view:NSView,context:Context){}
}
private struct CheckScopeWorkspace:View {
    @ObservedObject var state:CheckScopeState
    private var selection:Binding<String?>{Binding(get:{state.chosen.isEmpty ? nil:state.chosen},set:{state.chosen=$0 ?? ""})}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            WorkspaceHeading(title:"检查作业文件",subtitle:"1 文件范围  ›  2 检查报告",symbol:"doc.text.magnifyingglass")
            HStack{TextField("搜索文件或目录",text:$state.query).textFieldStyle(.roundedBorder).accessibilityLabel("搜索检查文件");Button("全选当前结果"){for row in state.visible where flag(row,"selectable"){state.selected.insert(string(row,"path"))}}.keyboardShortcut("a",modifiers:.command);Button("取消选择"){state.selected.removeAll()}}.disabled(state.busy)
            HSplitView {
                List(selection:selection){
                    OutlineGroup(checkFileTree(state.visible.filter{flag($0,"selectable")},flat:!state.query.isEmpty),children:\.children){node in fileRow(node)}
                    if state.visible.contains(where:{!flag($0,"selectable")}){WorkspaceDisclosure("已排除 · \(state.visible.filter{!flag($0,"selectable")}.count)"){ForEach(checkFileTree(state.visible.filter{!flag($0,"selectable")},flat:true)){node in fileRow(node)}}}
                }.listStyle(.inset).scrollContentBackground(.hidden).frame(minWidth:280,idealWidth:360,maxWidth:520,maxHeight:.infinity).accessibilityLabel("检查范围文件树").background(CheckSplitAnchor())
                VStack(alignment:.leading,spacing:8){Text(state.chosen.isEmpty ? "选择文件预览":state.chosen).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled);CheckPreviewHost(preview:state.preview).frame(maxWidth:.infinity,maxHeight:.infinity)}.padding(8).frame(minWidth:360,maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:AMAppearance.surface))
            }.frame(maxWidth:.infinity,maxHeight:.infinity)

            if state.busy{ProgressView().progressViewStyle(.linear)}
            Text(state.notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
            HStack{Text("文档 \(state.valid.filter{!flag($0,"image")}.count) · 已选 \(state.valid.count) · 图片 \(state.valid.filter{flag($0,"image")}.count) · 排除 \(state.records.filter{!flag($0,"selectable")}.count)").font(.caption).foregroundStyle(.secondary);Spacer();Text(ByteCountFormatter.string(fromByteCount:state.bytes,countStyle:.file)).font(.caption)}
            Divider()
            HStack{Button(state.busy ? "取消整理":"取消"){state.send("cancel")}.keyboardShortcut(.cancelAction);Text(state.hint).font(.caption).foregroundStyle(state.canStart ? Color.secondary:Color.orange);Spacer();Button("开始检查"){state.send("check")}.amPrimaryAction().disabled(!state.canStart).keyboardShortcut(.defaultAction)}
        }.padding(20).font(.system(size:13)).frame(minWidth:860,minHeight:560).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent)).amSecondaryActions().onChange(of:state.chosen){_ in state.send("preview")}
    }
    private func fileRow(_ node:CheckFileNode)->some View {
        HStack(spacing:6){if let row=node.record {Toggle("包含 \(node.id)",isOn:Binding(get:{state.selected.contains(node.id)},set:{if $0{state.selected.insert(node.id)}else{state.selected.remove(node.id)}})).labelsHidden().toggleStyle(.checkbox).disabled(!flag(row,"selectable"));Image(systemName:flag(row,"selectable") ? (flag(row,"image") ? "photo":"doc.text"):"minus.circle").foregroundStyle(.secondary)}else{Image(systemName:"folder").foregroundStyle(.secondary)}
            VStack(alignment:.leading,spacing:2){Text((node.id as NSString).lastPathComponent).lineLimit(1);if let row=node.record,!string(row,"reason").isEmpty{Text(string(row,"reason")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)}}
        }.tag(node.id).help(node.id).padding(.vertical,2)
    }
}
private struct WorkspaceHeading:View {
    var title:String
    var subtitle:String
    var symbol:String
    var body:some View {HStack(alignment:.center,spacing:12){Image(systemName:symbol).font(.title2).foregroundStyle(Color(nsColor:AMAppearance.accent)).frame(width:32);VStack(alignment:.leading,spacing:4){Text(title).font(.system(size:20,weight:.semibold));if !subtitle.isEmpty {Text(subtitle).font(.system(size:12)).foregroundStyle(.secondary)}}}}
}
@objc(AMCheckScopeController) @MainActor public final class AMCheckScopeController:NSViewController {
    private let state=CheckScopeState()
    @objc public var actionHandler:((NSDictionary)->Void)?{get{state.action}set{state.action=newValue}}
    public override func loadView(){view=NSHostingView(rootView:CheckScopeWorkspace(state:state))}
    @objc public func update(_ records:[NSDictionary],busy:Bool,notice:String){state.records=records;state.busy=busy;state.notice=notice;if !busy && !state.initialized {state.initialized=true;state.selected=Set(records.filter{flag($0,"selectable")}.map{string($0,"path")});state.initialSelection=state.selected;state.chosen=records.first(where:{flag($0,"selectable") && !flag($0,"image")}).map{string($0,"path")} ?? "";state.send("preview")}}
    @objc public func setProgress(_ notice:String){state.notice=notice}
    @objc public func setPreview(_ preview:NSView){state.preview=preview}
    @objc public var previewView:NSView?{state.preview}
    @objc public var hasUnsavedChanges:Bool{state.initialized && state.selected != state.initialSelection}
    @objc public var preparing:Bool{state.busy}
    @objc public func requestCheck(){if state.canStart{state.send("check")}}
}

private struct HelpTopic:Identifiable {
    let id:String
    let title:String
    let details:String
    let action:String
    let button:String
}
private let helpTopics:[HelpTopic]=[
    HelpTopic(id:"entry",title:"添加任务",details:"粘贴通知或截图，确认截止时间。",action:"quick",button:"快速录入"),
    HelpTopic(id:"calendar",title:"查看日历",details:"查看待办、周末和节假日。",action:"calendar",button:"打开日历"),
    HelpTopic(id:"courses",title:"发现新作业",details:"连接课程，检查并确认新作业。",action:"courses",button:"打开课程"),
    HelpTopic(id:"checking",title:"检查作业",details:"选择文件，查看问题和修改建议。",action:"tasks",button:"打开任务"),
    HelpTopic(id:"submissions",title:"提交与记录",details:"提交到个人仓库，查看提交记录。",action:"courses",button:"打开课程"),
    HelpTopic(id:"settings",title:"设置",details:"管理账户、提醒和更新。",action:"settings",button:"打开设置")
]
private struct HelpWorkspace:View {
    var action:(String)->Void
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:20){
            ForEach(helpTopics){topic in
                WorkspaceSection(topic.title){HStack(spacing:16){Text(topic.details).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true);Spacer(minLength:8);Button(topic.button){action(topic.action)}.fixedSize()}}.accessibilityElement(children:.contain).accessibilityIdentifier("help-topic-"+topic.id)
            }
        }.padding(24).frame(maxWidth:900,alignment:.leading).frame(maxWidth:.infinity,alignment:.leading)}.font(.system(size:13)).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent)).amSecondaryActions()
    }
}
@objc(AMHelpController) @MainActor public final class AMHelpController:NSViewController {
    @objc public var actionHandler:((String)->Void)?
    public override func loadView(){view=NSHostingView(rootView:HelpWorkspace(action:{[weak self] in self?.actionHandler?($0)}))}
}

// Shared editable task fields. Containers own save/cancel and source-specific
// evidence; this component owns the same labels, value summaries and hit areas.
private typealias TaskValueState<Value> = SwiftUI.State<Value>
private struct TaskSummaryRow<Content:View>:View {
    let title:String
    let summary:String
    var enabled=true
    @ViewBuilder let content:()->Content
    @TaskValueState<Bool> private var expanded=false
    var body:some View {
        Button {expanded=true} label:{HStack {Text(title);Spacer(minLength:12);Text(summary).foregroundStyle(.secondary).lineLimit(1);Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary)}.contentShape(Rectangle()).frame(minHeight:30)}
            .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(title).accessibilityValue(summary)
            .popover(isPresented:$expanded,arrowEdge:.trailing){VStack(alignment:.leading,spacing:12){HStack{Text(title).font(.headline);Spacer();Button("完成"){expanded=false}};content()}.padding(16).frame(width:300)}
    }
}
private func reminderSummary(_ offsets:[Int])->String {
    if offsets.isEmpty{return "不提醒"}
    let names=[10080:"7天",4320:"3天",1440:"1天",60:"1小时",0:"到期"]
    return Array(Set(offsets)).sorted(by:>).map{names[$0] ?? "\($0)分钟"}.joined(separator:"、")
}
private struct TaskReminderEditor:View {
    @Binding var offsets:[Int]
    @TaskValueState<String> private var custom=""
    @TaskValueState<String> private var error=""
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            ForEach([10080,4320,1440,60,0],id:\.self){value in
                Toggle(reminderSummary([value]),isOn:Binding(get:{offsets.contains(value)},set:{yes in var next=Set(offsets);if yes{next.insert(value)}else{next.remove(value)};offsets=Array(next).sorted(by:>)}))
            }
            let other=offsets.filter{![10080,4320,1440,60,0].contains($0)}
            ForEach(other,id:\.self){value in HStack{Text("提前 \(value) 分钟");Spacer();Button("移除"){offsets.removeAll{$0==value}}}}
            HStack{TextField("提前分钟数",text:$custom);Button("添加"){guard let value=Int(custom),value>=0,value<=525600 else{error="请输入 0–525600 分钟";return};offsets=Array(Set(offsets+[value])).sorted(by:>);custom="";error=""}}
            if !error.isEmpty {Text(error).font(.caption).foregroundStyle(.red)}
            HStack{Button("常用提醒"){offsets=[10080,4320,1440,60,0]};Button("关闭提醒"){offsets=[]}}
        }.toggleStyle(.checkbox)
    }
}
private struct TaskRecurrenceEditor:View {
    @Binding var rule:NSDictionary
    @Binding var scope:Int
    var preview=""
    var series=false
    private func field<T>(_ name:String,_ fallback:T)->Binding<T>{Binding(get:{rule[name] as? T ?? fallback},set:{let next=rule.mutableCopy() as! NSMutableDictionary;next[name]=$0;rule=next.copy() as! NSDictionary})}
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            Picker("方式",selection:field("mode","none")){Text("不重复").tag("none");Text("按固定日历").tag("fixed");Text("完成后重复").tag("completion")}
            if string(rule,"mode") != "none" && !string(rule,"mode").isEmpty {
                HStack{Text("每");TextField("间隔",text:field("intervalText","1")).frame(width:60);Picker("单位",selection:field("unit","week")){Text("天").tag("day");Text("周").tag("week");Text("月").tag("month");Text("年").tag("year")}.labelsHidden()}
                if string(rule,"mode")=="fixed" && string(rule,"unit")=="week" {
                    HStack(spacing:6){ForEach(0..<7,id:\.self){i in let day=(i+1)%7+1;Toggle(["一","二","三","四","五","六","日"][i],isOn:Binding(get:{(rule["weekdays"] as? [Int] ?? []).contains(day)},set:{yes in var days=Set(rule["weekdays"] as? [Int] ?? []);if yes{days.insert(day)}else{days.remove(day)};let next=rule.mutableCopy() as! NSMutableDictionary;next["weekdays"]=days.sorted();rule=next.copy() as! NSDictionary})).toggleStyle(.button).accessibilityLabel("每周"+["一","二","三","四","五","六","日"][i])}}
                }
                Picker("休息日",selection:field("holidayPolicy","keep")){Text("保持日期").tag("keep");Text("跳过").tag("skip");Text("提前至工作日").tag("previous");Text("顺延至工作日").tag("next")}
                Picker("结束",selection:field("endMode",0)){Text("一直重复").tag(0);Text("截至日期").tag(1);Text("限定次数").tag(2)}
                if (rule["endMode"] as? Int)==1 {DatePicker("截至",selection:field("until",Date()),displayedComponents:.date)}
                if (rule["endMode"] as? Int)==2 {TextField("次数",text:field("countText","10"))}
            }
            if series {Picker("应用范围",selection:$scope){Text("仅本次").tag(0);Text("本次及以后").tag(1)}}
            if !preview.isEmpty {Text(preview).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
        }
    }
}
private struct TaskFields:View {
    @Binding var title:String
    @Binding var subject:String
    @Binding var date:Date
    @Binding var notes:String
    @Binding var offsets:[Int]
    @Binding var priority:Int
    @Binding var recurrence:NSDictionary
    @Binding var seriesScope:Int
    var hasDate=true
    var confirmDate:(()->Void)?=nil
    var recurrenceEnabled=true
    var recurrencePreview=""
    var series=false
    var error=""
    var errorField=""
    var dateHint=""
    var notesHeight:CGFloat=120
    var compact=true
    var focusTitle=false
    @FocusState private var focus:String?
    @ViewBuilder private func problem(_ field:String)->some View {if !error.isEmpty && errorField==field {Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("task-error-"+field)}}
    private var recurrenceSummary:String {
        let mode=string(recurrence,"mode");if mode.isEmpty || mode=="none" {return "不重复"}
        let unit=["day":"天","week":"周","month":"月","year":"年"][string(recurrence,"unit")] ?? "周"
        return (mode=="completion" ? "完成后每":"每")+string(recurrence,"intervalText")+unit
    }
    var body:some View {
        Section {
            VStack(alignment:.leading,spacing:5){LabeledContent("名称"){TextField("任务名称",text:$title).focused($focus,equals:"title").accessibilityIdentifier("task-title")};problem("title")}
            LabeledContent("课程"){TextField("课程／分类",text:$subject).accessibilityIdentifier("task-subject")}
            VStack(alignment:.leading,spacing:5){
                if compact {VStack(alignment:.leading,spacing:6){Text("截止时间").foregroundStyle(.secondary);DatePicker("截止时间",selection:$date,displayedComponents:[.date,.hourAndMinute]).labelsHidden().accessibilityIdentifier("task-deadline")}}else{DatePicker("截止时间",selection:$date,displayedComponents:[.date,.hourAndMinute]).accessibilityIdentifier("task-deadline")}
                if !dateHint.isEmpty {Text(dateHint).font(.caption).foregroundStyle(.secondary)}
                if !hasDate,let confirmDate {Button("确认截止时间",action:confirmDate).accessibilityIdentifier("task-confirm-date")}
                problem("date")
            }
        }
        Section {
            TaskSummaryRow(title:"提醒",summary:reminderSummary(offsets)){TaskReminderEditor(offsets:$offsets)}
            TaskSummaryRow(title:"重复",summary:recurrenceSummary,enabled:recurrenceEnabled){TaskRecurrenceEditor(rule:$recurrence,scope:$seriesScope,preview:recurrencePreview,series:series)}.help(recurrenceEnabled ? "":"可在任务菜单另建周期安排")
            TaskSummaryRow(title:"优先级",summary:["普通","重要","紧急"][max(0,min(2,priority))]){Picker("优先级",selection:$priority){Text("普通").tag(0);Text("重要").tag(1);Text("紧急").tag(2)}.pickerStyle(.radioGroup)}
            problem("reminders");problem("recurrence")
        }
        Section("备注") {
            TextEditor(text:$notes).font(.body).frame(minHeight:notesHeight,idealHeight:notesHeight,maxHeight:notesHeight).accessibilityIdentifier("task-notes")
        }
        .onChange(of:errorField){value in if value=="title" {focus="title"}}.onAppear{if focusTitle{focus="title"}}
    }
}
@MainActor final class TaskDraftState:ObservableObject {
    @Published var values:NSDictionary=[:]
    @Published var error=""
    @Published var errorField=""
    @Published var notice=""
    @Published var supplementary:NSView?
    var baseline:NSDictionary=[:]
    var action:((String,NSDictionary)->Void)?
    var commitEditing:(()->Bool)?
    var effectiveValues:NSDictionary {
        var result=values as! [String:Any]
        for key in ["title","subject"] {result[key]=string(values,key).trimmingCharacters(in:.whitespacesAndNewlines)}
        if (result["subject"] as? String ?? "").isEmpty {result["subject"]="其他"}
        result["reminderOffsets"]=Array(Set(values["reminderOffsets"] as? [Int] ?? [])).sorted(by:>)
        if let recurrence=values["recurrence"] as? NSDictionary {
            if ["","none"].contains(string(recurrence,"mode")){result["recurrence"]=["mode":"none"]}
            else {var rule=recurrence as! [String:Any];if string(recurrence,"unit") != "week" || string(recurrence,"mode") != "fixed" {rule.removeValue(forKey:"weekdays")};let end=recurrence["endMode"] as? Int ?? 0;if end != 1 {rule.removeValue(forKey:"until")};if end != 2 {rule.removeValue(forKey:"countText")};result["recurrence"]=rule}
        }

        for key in ["recurrencePreview","dateHint","saveTitle","evidence","isNew","sourceLocked","series","supplementaryHeight","planningSummary"] {result.removeValue(forKey:key)}
        return result as NSDictionary
    }
    var dirty:Bool {!effectiveValues.isEqual(baseline)}
    func load(_ record:NSDictionary,reset:Bool) {if !values.isEqual(record){values=workspaceSnapshot(record) as! NSDictionary};if reset {baseline=effectiveValues;error="";errorField=""}}
    func field<T>(_ name:String,_ fallback:T)->Binding<T> {Binding(get:{self.values[name] as? T ?? fallback},set:{value in if name=="due",let before=self.values[name] as? Date,let date=value as? Date,floor(before.timeIntervalSince1970/60)==floor(date.timeIntervalSince1970/60){return};let next=self.values.mutableCopy() as! NSMutableDictionary;next[name]=value;if name=="due",!(self.values[name] as? Date == value as? Date){next["dateConfirmed"]=true};self.values=next.copy() as! NSDictionary;if self.errorField==name || (name=="due" && self.errorField=="date"){self.error="";self.errorField=""};self.action?("change",self.values)})}
    func save(){
        guard commitEditing?() ?? true else{return}
        if string(values,"title").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {error="请填写任务名称";errorField="title";return}
        if !flag(values,"dateConfirmed") {error="请确认截止日期和时间";errorField="date";return}
        action?("save",values)
    }
}
private struct TaskNativeSupplement:NSViewRepresentable {
    let content:NSView
    func makeNSView(context:Context)->NSView {let root=NSView();content.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(content);NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo:root.leadingAnchor),content.trailingAnchor.constraint(equalTo:root.trailingAnchor),content.topAnchor.constraint(equalTo:root.topAnchor),content.bottomAnchor.constraint(equalTo:root.bottomAnchor)]);return root}
    func updateNSView(_ nsView:NSView,context:Context){}
}
private struct TaskDraftView:View {
    @ObservedObject var state:TaskDraftState
    var body:some View {GeometryReader{geo in VStack(spacing:0){
        Form {
            TaskFields(title:state.field("title",""),subject:state.field("subject",""),date:state.field("due",Date()),notes:state.field("notes",""),offsets:state.field("reminderOffsets",[10080,4320,1440,60,0]),priority:state.field("priority",0),recurrence:state.field("recurrence",[:]),seriesScope:state.field("seriesScope",0),hasDate:flag(state.values,"dateConfirmed"),confirmDate:{let next=state.values.mutableCopy() as! NSMutableDictionary;next["dateConfirmed"]=true;state.values=next;state.action?("change",next)},recurrenceEnabled:!flag(state.values,"sourceLocked"),recurrencePreview:string(state.values,"recurrencePreview"),series:flag(state.values,"series"),error:state.error,errorField:state.errorField,dateHint:string(state.values,"dateHint"),notesHeight:max(90,geo.size.height-(geo.size.width<430 ? 560:460)),compact:geo.size.width<430,focusTitle:flag(state.values,"isNew"))
            if !string(state.values,"evidence").isEmpty {Section{WorkspaceDisclosure("老师原文与来源"){Text(string(state.values,"evidence")).textSelection(.enabled)}}}
            if let supplementary=state.supplementary {Section {TaskSummaryRow(title:"计划与子任务",summary:string(state.values,"planningSummary")){ScrollView{TaskNativeSupplement(content:supplementary).frame(height:CGFloat((state.values["supplementaryHeight"] as? NSNumber)?.doubleValue ?? 190))}.frame(height:min(420,CGFloat((state.values["supplementaryHeight"] as? NSNumber)?.doubleValue ?? 190)))}}}
        }.formStyle(.grouped).controlSize(.regular).textFieldStyle(.roundedBorder).environment(\.timeZone,TimeZone(identifier:string(state.values,"timeZone")) ?? .current)
        Divider()
        VStack(alignment:.leading,spacing:8){
            if !state.error.isEmpty && state.errorField.isEmpty {HStack(alignment:.top){Text(state.error).foregroundStyle(.red).textSelection(.enabled);Spacer();Button{state.error=""}label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel("关闭提示")}}
            if !state.notice.isEmpty {Text(state.notice).font(.caption).foregroundStyle(.secondary)}
            HStack{
                if flag(state.values,"isNew"){Button("从文字或截图录入…"){state.action?("recognize",state.values)}}
                else {Menu("更多"){Button("检查作业文件…"){state.action?("check",state.values)};Button("提交作业…"){state.action?("submit",state.values)};Button("提交记录"){state.action?("history",state.values)}}}

                Spacer(minLength:8);Button("取消"){state.action?("cancel",state.values)}.keyboardShortcut(.cancelAction)
                WorkspaceButton(title:string(state.values,"saveTitle").isEmpty ? "保存":string(state.values,"saveTitle"),prominent:true,identity:"task-save",saveShortcut:true){state.save()}.fixedSize()
            }
        }.padding(12)
    }.background(Color(nsColor:.windowBackgroundColor))}}
}
@objc(AMTaskFormController) @MainActor public final class AMTaskFormController:NSViewController {
    private let state=TaskDraftState()
    @objc public var actionHandler:((String,NSDictionary)->Void)? {didSet{state.action=actionHandler}}
    @objc public var hasUnsavedChanges:Bool {state.dirty}
    @objc public var snapshot:NSDictionary {state.values}
    @objc public func loadRecord(_ record:NSDictionary,resetBaseline:Bool){state.load(record,reset:resetBaseline)}
    @objc public func setValidation(_ message:String,field:String){state.error=message;state.errorField=field}
    @objc public func setNotice(_ text:String){state.notice=text}
    @objc public func setSupplementaryView(_ view:NSView?){state.supplementary=view}
    @objc public func captureEditingPosition()->NSDictionary {
        guard let text=view.window?.firstResponder as? NSTextView else{return [:]}
        let target=(text.isFieldEditor ? text.delegate as? NSView:text)
        guard let target,target.isDescendant(of:view) else{return [:]}
        let position:NSDictionary=["target":target,"selection":NSValue(range:text.selectedRange())]
        _ = view.window?.makeFirstResponder(nil)
        return position
    }
    @objc public func restoreEditingPosition(_ position:NSDictionary){
        guard let target=position["target"] as? NSView,target.isDescendant(of:view) else{return}
        DispatchQueue.main.async{[weak self,weak target] in guard let self,let target else{return};_ = self.view.window?.makeFirstResponder(target);if let text=self.view.window?.firstResponder as? NSTextView,let selection=position["selection"] as? NSValue{let range=selection.rangeValue;text.setSelectedRange(NSRange(location:min(range.location,text.string.utf16.count),length:min(range.length,max(0,text.string.utf16.count-range.location))))}}
    }
    @objc public func save(){state.save()}
    public override func loadView(){view=NSHostingView(rootView:TaskDraftView(state:state));state.commitEditing={[weak self] in self?.view.window?.makeFirstResponder(nil) ?? true}}
}
