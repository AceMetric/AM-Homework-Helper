import AppKit
import SwiftUI

// One semantic palette for SwiftUI and the existing AppKit drawing layer.
@objc(AMAppearance) public final class AMAppearance:NSObject {
    private static func layer(_ light:UInt32,_ dark:UInt32)->NSColor {NSColor(name:nil){appearance in
        let value=appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark:light
        return NSColor(srgbRed:CGFloat((value >> 16)&255)/255,green:CGFloat((value >> 8)&255)/255,blue:CGFloat(value&255)/255,alpha:1)
    }}
    @objc public static var canvas:NSColor {layer(0xf5f6f8,0x242528)}
    @objc public static var surface:NSColor {layer(0xffffff,0x2e3034)}
    @objc public static var sidebar:NSColor {layer(0xedefF3,0x202125)}
    @objc public static var separator:NSColor {.separatorColor}
    @objc public static var ink:NSColor {.labelColor}
    @objc public static var muted:NSColor {.secondaryLabelColor}
    @objc public static var accent:NSColor {.systemBlue}
    @objc public static var selection:NSColor {accent.withAlphaComponent(0.12)}
}
private struct WorkspaceSection<Content:View>:View {
    @Environment(\.colorSchemeContrast) private var contrast
    let title:String
    let content:Content
    init(_ title:String,@ViewBuilder content:()->Content){self.title=title;self.content=content()}
    var body:some View {
        VStack(alignment:.leading,spacing:12){Text(title).font(.system(size:13,weight:.semibold));content}
            .padding(16).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(nsColor:AMAppearance.surface))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(Color(nsColor:contrast == .increased ? AMAppearance.muted:AMAppearance.separator).opacity(contrast == .increased ? 1:0.55),lineWidth:contrast == .increased ? 1.5:0.5))
            .clipShape(RoundedRectangle(cornerRadius:10))
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
    @Published var notes = ""
    @Published var date = Date()
    @Published var hasDate = false
    @Published var dateConfirmed = false
    @Published var reminders = true
    @Published var reminderOffsets: Set<Int> = [10080,4320,1440,60,0]
    @Published var dirty = false
    @Published var message = ""
    @Published var failed = false
    @Published var saving = false
    @Published var paused = false
    @Published var batchPreview: [ReviewBatchItem]?
    var activeRecord: NSDictionary?
    var save: (([NSDictionary]) -> String)?
    var sourceResolver: ((String)->NSDictionary?)?
    var didSave: (() -> Void)?
    var originalTitle = "", originalNotes = ""
    var current: NSDictionary? { activeRecord }
    var visible: [NSDictionary] {
        records.filter { string($0,"reviewStatus") != "已导入" && (query.isEmpty || [string($0,"suggestedTitle"),string($0,"title"),string($0,"repository"),string($0,"path")].joined(separator:" ").localizedCaseInsensitiveContains(query)) }
    }
    var disabledReason: String {
        saving ? "正在保存，请稍候…" : paused ? "课程操作正在进行，请等待结束后保存。" : current == nil ? "请先选择一项待审核作业。" : ""
    }
    var sourceChanged: Bool {
        guard let current else {return false}
        guard let latest=latestSource(identifier(current)) else {return true}
        return ["blobSHA","kind","dateText","due","suggestedDue","needsDate","needsTime"].contains { key in
            !NSDictionary(dictionary:["value":current[key] ?? NSNull()]).isEqual(to:["value":latest[key] ?? NSNull()])
        }
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
    func select(_ record: NSDictionary) { guard !saving,identifier(record) != selected, resolve() else { return };message="";failed=false;load(record) }
    func validation(_ record:NSDictionary, editing:Bool)->String {
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
        if editing {draft["notes"]=notes;draft["reminderOffsets"]=reminders ? reminderOffsets.sorted(by:>) : [Int]()}
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
        message="已保存 \(payloads.count) 项作业。提醒状态可在设置中查看。"
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
        VStack(alignment:.leading,spacing:16) {
            Text(record["existingTask"] == nil ? "审核作业" : "编辑作业").font(.title3.bold())
            if string(record,"reviewStatus")=="已导入" {Text("已加入任务，修改后保存即可同步。").foregroundStyle(.secondary)}
            TextField("作业名称",text:editing(\.title)).textFieldStyle(.roundedBorder)
            WorkspaceSection("截止时间") {
                VStack(alignment:.leading,spacing:10) {
                    Text(string(record,"dateText").isEmpty ? "老师未说明完整截止时间" : "老师原文：\(string(record,"dateText"))").textSelection(.enabled)
                    if let warnings=record["warnings"] as? [String] { ForEach(Array(warnings.enumerated()),id:\.offset){Text($0.element).foregroundStyle(.orange)} }
                    if let due=record["suggestedDue"] as? Date {
                        Text("原文日期建议：\(due.formatted(date:.abbreviated,time:.shortened))")
                        if let basis=record["dateBasis"] as? NSDictionary, let date=basis["date"] as? Date { Text("依据：\(date.formatted()) · \(String(string(basis,"commit").prefix(7)))").font(.caption).foregroundStyle(.secondary) }
                    }
                    DatePicker("作业 DDL",selection:Binding(get:{state.date},set:{state.date=$0;state.hasDate=true;state.dateConfirmed=true;state.dirty=true}),displayedComponents:[.date,.hourAndMinute])
                    if !state.hasDate || !state.dateConfirmed {
                        Text("请补全并核对截止日期和时间；当前日期不会自动保存。").foregroundStyle(.orange)
                        Button("确认填写的截止时间"){state.hasDate=true;state.dateConfirmed=true;state.dirty=true}
                    }
                    Text("课程时区：\(string(record,"timeZone"))").font(.caption).foregroundStyle(.secondary)
                    Toggle("启用提醒",isOn:editing(\.reminders))
                    if state.reminders {
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:85))],alignment:.leading) {
                            ForEach([10080,4320,1440,60,0],id:\.self){offset in
                                Toggle([10080:"7天",4320:"3天",1440:"1天",60:"1小时",0:"到期"][offset]!,isOn:Binding(get:{state.reminderOffsets.contains(offset)},set:{if $0 {state.reminderOffsets.insert(offset)}else{state.reminderOffsets.remove(offset)};state.dirty=true})).toggleStyle(.checkbox)
                            }
                        }
                        let custom = state.reminderOffsets.subtracting([10080,4320,1440,60,0]).sorted(by:>)
                        if !custom.isEmpty { Text("保留自定义提醒：\(custom.map{"提前\($0)分钟"}.joined(separator:"、"))").font(.caption).foregroundStyle(.secondary) }
                        Button("使用全部常用提醒"){state.reminderOffsets=[10080,4320,1440,60,0];state.dirty=true}
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(4)
                .environment(\.timeZone,TimeZone(identifier:string(record,"timeZone")) ?? .current)
            }
            VStack(alignment:.leading,spacing:6) { Text("备注（可修改或清空）").fontWeight(.medium); TextEditor(text:editing(\.notes)).frame(minHeight:140).padding(6).background(Color(nsColor:.textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Color(nsColor:AMAppearance.separator),lineWidth:0.5)) }
            DisclosureGroup("老师原文与来源") {
                VStack(alignment:.leading,spacing:8) {
                    Text("\(string(record,"repository")) / \(string(record,"path")):\((record["line"] as? NSNumber)?.intValue ?? 1)").font(.caption).foregroundStyle(.secondary)
                    Text(string(record,"snippet")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    if let attachments=record["attachments"] as? [NSDictionary] { ForEach(workspaceRows(attachments,key:"path")){Text("附件：\(string($0.record,"path"))\n\(string($0.record,"snippet"))").textSelection(.enabled)} }
                }.padding(4)
            }
        }.padding(.horizontal,16).padding(.vertical,8)
    }
}
private struct ReviewFeedback:View {
    @ObservedObject var state:ReviewState
    var body:some View {
        if !state.message.isEmpty {
            VStack(alignment:.leading,spacing:8) {
                Label(state.message,systemImage:state.failed ? "exclamationmark.circle.fill":"checkmark.circle").textSelection(.enabled)
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
        button.bezelStyle = .rounded;button.controlSize = .large
        button.setContentHuggingPriority(.required,for:.horizontal)
        return button
    }
    func updateNSView(_ button:NSButton,context:Context){
        context.coordinator.action=action;button.title=title;button.isEnabled=enabled
        button.bezelColor=prominent ? .controlAccentColor:nil
        button.setAccessibilityIdentifier(identity)
        button.keyEquivalent=saveShortcut ? "\r":"";button.keyEquivalentModifierMask = .command
    }
}
private struct ReviewSaveBar:View {
    @ObservedObject var state:ReviewState
    let advance:Bool
    var body:some View {
        HStack {
            if state.saving {ProgressView().controlSize(.small)}
            Text(state.disabledReason.isEmpty ? (state.dirty ? "有未保存修改" : "核对后保存至任务") : state.disabledReason).font(.caption).foregroundStyle(.secondary)
            Spacer()
            WorkspaceButton(title:advance ? "保存并下一项" : (state.current?["existingTask"] == nil ? "确认作业":"保存修改"),enabled:state.disabledReason.isEmpty,prominent:true,identity:"review-save",saveShortcut:true){state.saveCurrent(advance:advance)}.fixedSize().help(state.disabledReason)
        }
    }
}
private struct ReviewWorkspace: View {
    @ObservedObject var state: ReviewState
    @FocusState private var searchFocused:Bool
    @FocusState private var listFocused:Bool
    private var entries:some View {
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:4) {
                        ForEach(workspaceRows(state.visible)) { row in
                            let record = row.record
                            HStack(alignment:.top,spacing:8) {
                                Toggle("选择",isOn:Binding(get:{state.checked.contains(identifier(record))},set:{if $0 {state.checked.insert(identifier(record))}else{state.checked.remove(identifier(record))}})).labelsHidden().toggleStyle(.checkbox).accessibilityLabel("选择\(string(record,"title"))").disabled(string(record,"reviewStatus")=="已导入")
                                Button { state.select(record) } label: {
                                    VStack(alignment:.leading,spacing:5) {
                                        Text(string(record,"suggestedTitle").isEmpty ? string(record,"title") : string(record,"suggestedTitle")).font(.system(size:13,weight:.medium)).lineLimit(2)
                                        Text(string(record,"repository")).font(.caption).foregroundStyle(.secondary)
                                        Label(record["existingTask"] == nil ? "新作业" : "更新建议",systemImage:record["existingTask"] == nil ? "tray" : "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth:.infinity,alignment:.leading).padding(8).background(state.selected == identifier(record) ? Color(nsColor:AMAppearance.selection) : Color.clear).cornerRadius(8)
                                }.buttonStyle(.plain)
                            }.padding(.horizontal,4)
                        }
                    }.padding(.vertical,4)
                }.focusable().focused($listFocused)
                    .overlay(Button("全选"){state.selectAll()}.keyboardShortcut("a",modifiers:.command).disabled(!listFocused).frame(width:0,height:0).clipped().accessibilityHidden(true))
    }
    private var details:some View {
                ScrollView {
                    if let record=state.current {
                        ReviewDetails(state:state,record:record)
                    } else {
                        VStack(spacing:12){Image(systemName:"tray").font(.largeTitle).foregroundStyle(.secondary);Text("暂无待审核作业");Text("检查课程后，需确认的作业会显示在这里。").foregroundStyle(.secondary)}.frame(maxWidth:.infinity,minHeight:240)
                    }
                }.frame(minWidth:300)    }
    var body: some View {
        VStack(spacing:12) {
            WorkspaceHint(key:"review",text:"选中后直接在侧边核对；完整条目可全选批量确认，保存成功即从列表移除。")
            HStack {
                TextField("搜索名称、课程或文件",text:$state.query).textFieldStyle(.roundedBorder).focused($searchFocused)
                Text("已选 \(state.checked.count) / \(state.visible.count) 项").foregroundStyle(.secondary)
                WorkspaceButton(title:"全选当前结果",enabled:!state.saving && !state.visible.isEmpty,identity:"review-select-all"){state.selectAll()}.fixedSize()
                Button("取消选择"){state.clearChecks()}.disabled(state.checked.isEmpty || state.saving)
                WorkspaceButton(title:"确认所选 \(state.checked.count) 项",enabled:!state.checked.isEmpty && !state.paused && !state.saving,identity:"review-preview-batch"){state.saveChecked()}.fixedSize()
            }
            if state.batchPreview==nil {ReviewFeedback(state:state)}
            if let preview=state.batchPreview {
                ReviewBatchPreview(state:state,items:preview)
            } else {GeometryReader { geometry in
                if geometry.size.width<760 {VSplitView{entries.frame(minHeight:140,idealHeight:180,maxHeight:220);details}}
                else {HSplitView{entries.frame(minWidth:220,idealWidth:280,maxWidth:340);details}}
            }}
            ReviewSaveBar(state:state,advance:true)
        }.padding(12).font(.system(size:13)).tint(Color(nsColor:AMAppearance.accent)).onChange(of:state.searchToken){_ in searchFocused=true}
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
    @objc public var sourceHandler: ((String)->NSDictionary?)? {get{state.sourceResolver}set{state.sourceResolver=newValue}}
    @objc public var hasUnsavedChanges: Bool {state.dirty}
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
    @Published var dirty=false
    var save:((NSDictionary,String)->String)?
    var action:((String)->Void)?
    func apply(_ settings:NSDictionary) {mode=string(settings,"mode");endpoint=string(settings,"endpoint");model=string(settings,"model");automatic=flag(settings,"automaticImport");localAutomatic=settings["localAutomatic"] as? Bool ?? true;modelDigest=string(settings,"modelDigest");cloudCourses=Set(settings["cloudCourses"] as? [String] ?? []);availableCourses=settings["availableCourses"] as? [String] ?? [];localStatus=string(settings,"localStatus");lastMode=mode;modeProfiles[mode]=(endpoint,model,modelDigest);key="";dirty=false}
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
        let result=save?(["mode":mode,"endpoint":endpoint,"model":model,"automaticImport":automatic,"localAutomatic":localAutomatic,"modelDigest":modelDigest,"cloudCourses":Array(cloudCourses).sorted()] as NSDictionary,key) ?? "无法保存设置。"
        message=result.isEmpty ? "设置已保存；下次检查作业时生效。" : result
        if result.isEmpty {key="";dirty=false};return result.isEmpty
    }
}
private struct SettingsWorkspace:View {
    @ObservedObject var state:SettingsState
    private func binding<T>(_ key:ReferenceWritableKeyPath<SettingsState,T>)->Binding<T>{Binding(get:{state[keyPath:key]},set:{state[keyPath:key]=$0;state.dirty=true})}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("设置").font(.title2.bold())
                WorkspaceSection("作业识别") {
                    VStack(alignment:.leading,spacing:12) {
                        Label("规则检查免费可用；复杂文档可交给助手识别。",systemImage:"checkmark.shield").foregroundStyle(.secondary)
                        DisclosureGroup("高级识别：本地模型与云 API") {
                            VStack(alignment:.leading,spacing:12) {
                        Picker("识别方式",selection:binding(\.mode)){Text("免费规则").tag("rules");Text("本地 Ollama").tag("local");Text("云端 API").tag("cloud")}
                        if state.mode != "rules" {
                            if state.mode=="cloud" {TextField("API 基础地址，例如 https://服务地址/v1",text:binding(\.endpoint)).textFieldStyle(.roundedBorder);TextField("模型名称",text:binding(\.model)).textFieldStyle(.roundedBorder)}
                            else {
                                HStack{Button("检测本地服务"){state.probe("models")}.disabled(state.localBusy);Button("测试识别"){state.probe("test")}.disabled(state.localBusy || state.model.isEmpty)}
                                if !state.installedModels.isEmpty {Picker("已安装模型",selection:binding(\.model)){Text("请选择模型").tag("");if !state.model.isEmpty && !state.installedModels.contains(where:{string($0,"name")==state.model}){Text(state.model+"（当前配置）").tag(state.model)};ForEach(state.installedModels.indices,id:\.self){i in Text(string(state.installedModels[i],"name")).tag(string(state.installedModels[i],"name"))}}.onChange(of:state.model){name in state.modelDigest=state.installedModels.first(where:{string($0,"name")==name}).map{string($0,"digest")} ?? ""}}
                                else {Text(state.model.isEmpty ? "检测后选择这台 Mac 已安装的模型。":"当前模型："+state.model).foregroundStyle(.secondary)}
                                Toggle("检查新作业时自动使用本地模型",isOn:binding(\.localAutomatic))
                                Text("关闭后仍可在课程“更多”中手动重新识别。规则结果先显示，模型随后补充。").foregroundStyle(.secondary)
                                if !state.localStatus.isEmpty {Text(state.localStatus).textSelection(.enabled)}
                                DisclosureGroup("高级：服务地址与模型名称"){VStack(spacing:8){TextField("本地地址",text:binding(\.endpoint)).textFieldStyle(.roundedBorder);TextField("已安装模型名称",text:binding(\.model)).textFieldStyle(.roundedBorder)}}
                            }
                            if state.mode == "cloud" {
                                SecureField("此服务的 API 密钥（留空保留原值）",text:binding(\.key)).textFieldStyle(.roundedBorder)
                                Text("仅发送勾选课程的老师文档：").font(.caption)
                                ForEach(state.availableCourses,id:\.self) { course in
                                    Toggle(course,isOn:Binding(get:{state.cloudCourses.contains(course)},set:{if $0 {state.cloudCourses.insert(course)}else{state.cloudCourses.remove(course)};state.dirty=true}))
                                }
                                if state.availableCourses.isEmpty {Text("先在课程页添加课程，再启用云端识别。").foregroundStyle(.secondary)}
                                Text("不发送个人任务或凭据。每天最多20次请求，包含失败；可能产生服务费用。").foregroundStyle(.secondary)
                            }
                            else {Text("仅使用本机已安装模型，不自动下载；失败后继续规则识别。").foregroundStyle(.secondary)}
                        }
                            }.padding(.top,12)
                        }
                        Toggle("自动加入完整明确日期的新作业",isOn:binding(\.automatic))
                        Text("相对日期、缺失时间和考试不会自动加入；已有任务更新仍需审核。").foregroundStyle(.secondary)
                        Button("保存识别设置"){_ = state.persist()}.buttonStyle(.borderedProminent).disabled(state.localBusy)
                        if !state.message.isEmpty {Text(state.message).textSelection(.enabled)}
                    }.padding(8).frame(maxWidth:.infinity,alignment:.leading)
                }
                WorkspaceSection("助手识别 · Skill") {VStack(alignment:.leading,spacing:12){Text("准备多门课程的新材料，复制指令交给助手；结果自动接回待审核，无需手动导入。").foregroundStyle(.secondary);HStack{Button("助手识别"){state.action?("skill-export")}.buttonStyle(.borderedProminent);Button("批次与进度…"){state.action?("skill-status")};Spacer()};DisclosureGroup("课程与兼容操作"){HStack{Button("调整课程…"){state.action?("skill-courses")};Button("重新分析全部…"){state.action?("skill-all")};Button("手动导入…"){state.action?("skill-import")}}};Text("不会自动发送老师原文或启动付费分析。").font(.caption).foregroundStyle(.secondary)}}
                WorkspaceSection("账户与提醒") {HStack{Button("GitHub 账户…"){state.action?("account")};Button("提醒设置与测试…"){state.action?("notifications")};Button("排查提醒…"){state.action?("notification-help")};Spacer()}.padding(8)}
                WorkspaceSection("软件更新") {HStack{Button("检查更新…"){state.action?("check-update")};Button("自动检查设置…"){state.action?("updates")};Spacer()}.padding(8)}
                WorkspaceSection("数据与反馈"){HStack{Button("恢复任务…"){state.action?("recovery")};Button("诊断与反馈…"){state.action?("diagnostics")};Spacer()}}
                DisclosureGroup("高级设置") {Button("GitHub 登录与兼容设置…"){state.action?("advanced")}.padding(.top,8)}
                HStack{Spacer();Button("完成"){state.action?("close")}.keyboardShortcut(.cancelAction)}
            }.padding(24)
        }.onChange(of:state.mode){state.changeMode($0)}.font(.system(size:13)).frame(minWidth:540,minHeight:520).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent))
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
    func reviewRecord(_ record:NSDictionary)->NSDictionary? {
        if let source=record["reviewRecord"] as? NSDictionary {return source}
        if !flag(record,"confirmed") && (string(record,"kind").isEmpty || string(record,"kind")=="assignment") {return record}
        return nil
    }
    @discardableResult func select(_ id:String)->Bool {
        guard let record=records.first(where:{identifier($0)==id}) else{return false}
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
    private func kind(_ record:NSDictionary)->String {flag(record,"confirmed") ? (flag(record,"completed") ? "已完成":"待完成") : string(record,"reviewStatus")=="有更新" ? "有更新，待审核" : ["assignment":"作业","exam":"考试","classroom":"课上任务","unknown":"待确认类型"][string(record,"kind")] ?? "作业"}
    private var entries:some View {
        List(selection:Binding(get:{state.selected},set:{if let id=$0 {state.select(id)}})) {
            ForEach(workspaceRows(state.records)) { row in
                let record=row.record
                VStack(alignment:.leading,spacing:6) {
                    Text(string(record,"suggestedTitle").isEmpty ? string(record,"title") : string(record,"suggestedTitle")).fontWeight(.medium).lineLimit(2)
                    HStack {Label(kind(record),systemImage:string(record,"kind")=="exam" ? "doc.text" : "checklist");Spacer();if let due=record["due"] as? Date {Text(due,format:.dateTime.month().day().hour().minute())}}
                        .font(.caption).foregroundStyle(.secondary)
                    Text(string(record,"path")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.padding(.vertical,5).tag(identifier(record))
            }
        }.listStyle(.inset).frame(minWidth:240)
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
                } else {VStack(alignment:.leading,spacing:12){Label(state.empty.isEmpty ? "选择课程内容查看详情":state.empty,systemImage:"tray");Text("检查只读取老师内容；同步文件与提交作业是独立操作。").foregroundStyle(.secondary)}}
            }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
        }.frame(minWidth:260)
    }
    private var detailPane:some View {
        VStack(spacing:0){WorkspaceHint(key:"course-review",text:"核对侧边的名称、截止时间和备注后确认；保存成功即移出审核列表。").padding(.horizontal,12);ReviewFeedback(state:state.review).padding(.horizontal,12);details;if let record=state.current,!flag(record,"confirmed"),state.reviewRecord(record) != nil {Divider();ReviewSaveBar(state:state.review,advance:false).padding(12)}}
    }
    var body:some View {
        GeometryReader { geometry in
            if state.records.isEmpty {detailPane}
            else if geometry.size.width<760 {VSplitView{entries.frame(minHeight:160,idealHeight:220);detailPane.frame(minHeight:180)}}
            else {HSplitView{entries.frame(idealWidth:300,maxWidth:360);detailPane}}
        }.font(.system(size:13)).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent))
    }
}
@objc(AMCourseController)
@MainActor public final class AMCourseController:NSViewController {
    private let state=CourseState()
    @objc public var actionHandler:((String,String)->Void)? {get{state.action}set{state.action=newValue}}
    @objc public var saveHandler:(([NSDictionary])->String)? {get{state.review.save}set{state.review.save=newValue}}
    @objc public var sourceHandler:((String)->NSDictionary?)? {get{state.review.sourceResolver}set{state.review.sourceResolver=newValue}}
    @objc public var paused:Bool {get{state.review.paused}set{state.review.paused=newValue;state.paused=newValue}}
    @objc public var hasUnsavedChanges:Bool {state.review.dirty}
    @objc public func resolveUnsavedChanges()->Bool {state.review.resolve()}
    @objc public func discardChanges(){state.review.dirty=false;state.review.refresh(state.review.records)}
    @objc public func saveCurrent()->Bool {state.review.saveCurrent(advance:false)}
    @objc public func selectRecord(withID id:String)->Bool {state.select(id)}
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
            WorkspaceHeading(title:state.step < 4 ? (state.step==0 && string(state.context,"code").isEmpty ? "欢迎使用 AM Helper":steps[max(0,min(3,state.step))]):"配置已完成",subtitle:state.step==0 ? "连接课程，或直接使用本机作业功能。":"每一步成功的配置都会保留。",symbol:state.step==0 ? "graduationcap":"checklist")
            content
            if state.busy {HStack{ProgressView().controlSize(.small);Text(state.step==0 ? "正在等待登录，其他课程数据会保留。":"正在逐门处理；可以收起引导，成功结果会保留。").foregroundStyle(.secondary)}}
            Text(state.message).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Divider()
            footer
        }.padding(24).frame(minWidth:620,minHeight:450).font(.system(size:13)).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent))
    }
    @ViewBuilder private var content:some View {
        if state.step==0 {
            ScrollView {VStack(alignment:.leading,spacing:16){
                Label("用浏览器连接 GitHub，无需 SSH 或额外安装工具。",systemImage:"person.crop.circle.badge.checkmark")
                DisclosureGroup("登录权限与隐私说明"){Text(official ? "授权页面会显示 GitHub CLI，这是软件内置的 GitHub 官方登录工具。它申请 repo、read:org、gist 权限，范围比所选课程更宽；本应用仅处理你选择的课程，登录令牌只保存在这台 Mac 的钥匙串。":"你在高级设置中选择了旧兼容登录，不使用内置官方工具。旧 OAuth 可能受组织应用限制，旧 GitHub App 需单独安装授权及本机上游凭据。登录令牌只存本机。").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
                Text(official ? "不需要申请批准本项目应用。GitHub 登录、双重验证及学校 SSO 仍由你本人完成，课程访问权限需要已具备。":"如需简化配置，可取消引导，在高级登录设置选择 GitHub 官方登录。").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if !string(state.context,"code").isEmpty {
                    Text(string(state.context,"code")).font(.system(size:30,weight:.semibold,design:.monospaced)).textSelection(.enabled).accessibilityLabel("GitHub 验证码")
                    HStack {Button("复制代码"){state.send("copyCode")};Button("打开 GitHub"){state.send("openLogin")}}
                    Text("在网页输入上方代码并确认。完成后这里会自动继续。").foregroundStyle(.secondary)
                }
                if !string(state.context,"detail").isEmpty {DisclosureGroup("详情"){Text(string(state.context,"detail")).font(.caption).textSelection(.enabled)}}
            }.frame(maxWidth:.infinity,alignment:.leading)}
        } else if state.step==1 {
            Text("勾选自己的课程 fork，老师仓库和读取权限将自动核验。").foregroundStyle(.secondary)
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
            Text("选择课程总文件夹可批量匹配；缺少文件的课程可下载到同一个位置。").foregroundStyle(.secondary)
            HStack{Button("选择课程总文件夹…"){state.send("find")};Button("下载缺少的课程…"){state.send("download")};Spacer();Button("重试权限检测"){state.send("retry")}}.disabled(state.busy)
            courseRows
        } else if state.step==3 {
            Text("检查只读取老师内容，不合并文件、不提交或推送。失败课程可单独处理，已有结果保留。").foregroundStyle(.secondary)
            courseRows
        } else {
            ScrollView {VStack(alignment:.leading,spacing:20){
                tip("检查新作业","发现老师的新内容，不合并或推送。","magnifyingglass")
                tip("审核作业","核对名称、内容和截止时间，保存后进入任务、日历和提醒。","tray")
                tip("同步课程文件","更新本地文件，并安全更新你自己的 fork。","arrow.triangle.2.circlepath")
                tip("提交作业","选择文件、预览并填写说明，只推送个人仓库。","paperplane")
                Text("这些提示不会自动执行同步或提交。可从侧栏“开始使用”随时重看。").foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading)}
        }
    }
    private func tip(_ title:String,_ description:String,_ symbol:String)->some View {HStack(alignment:.top,spacing:12){Image(systemName:symbol).frame(width:24).foregroundStyle(Color.accentColor);VStack(alignment:.leading,spacing:4){Text(title).fontWeight(.semibold);Text(description).foregroundStyle(.secondary)}}}
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
                if !string(record,"detail").isEmpty {DisclosureGroup("详情"){Text(string(record,"detail")).font(.caption).textSelection(.enabled)}}
                if !string(record,"helpURL").isEmpty,let url=URL(string:string(record,"helpURL")){Link("打开 GitHub 处理…",destination:url)}
            }.padding(.vertical,6)
        }
    }
    private var footer:some View {
        HStack {
            Button(state.busy && state.step==0 ? "取消登录":(state.step==4 ? "稍后查看":"下次继续")){state.send("close")}.keyboardShortcut(.cancelAction)
            if state.step>0 && state.step<4 {Button("返回"){state.send("back")}.disabled(state.busy)}
            Spacer()
            if state.step==0 {if !state.busy && string(state.context,"code").isEmpty{Button("先使用本机作业功能"){state.send("local")}};Button("连接 GitHub 课程"){state.send("login")}.disabled(state.busy || !string(state.context,"code").isEmpty).keyboardShortcut(.defaultAction)}
            else if state.step==1 {Button("下一步：核验课程"){state.send("select")}.disabled(state.busy || state.selected.isEmpty).keyboardShortcut(.defaultAction)}
            else if state.step==2 {Button("确认并开始检查"){state.send("link-check")}.disabled(state.busy || !state.records.contains{!flag($0,"invalid") && !(state.paths[string($0,"fork")] ?? string($0,"path")).isEmpty}).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)}
            else if state.step==3 {Button("重试未完成课程"){state.send("retry-check")}.disabled(state.busy);Button("完成配置"){state.send("finish")}.disabled(state.busy).keyboardShortcut(.defaultAction)}
            else {Button("重新运行配置引导"){state.send("restart")}.disabled(state.busy);Button("查看课程"){state.send("courses")}.keyboardShortcut(.defaultAction);Button("查看待审核"){state.send("review")}}
        }
    }
}
@objc(AMSetupController)
@MainActor public final class AMSetupController:NSViewController {
    private let state=SetupState()
    @objc public var actionHandler:((NSDictionary)->Void)?{get{state.action}set{state.action=newValue}}
    @objc public func updateRecords(_ records:[NSDictionary],step:Int,busy:Bool,message:String){state.update(records,step:step,busy:busy,message:message)}
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
            WorkspaceHint(key:"skill",text:"准备材料 → 复制指令给助手 → 结果自动接回；不会自动发送材料。")
            HStack{Text("助手识别批次").font(.title2.bold());Spacer();Button("清理已完成材料"){state.action?("clean","")}.disabled(state.busy);Button("返回课程"){state.action?("close","")}}
            Text("等待助手期间可以继续使用。接回后仍需审核；重试只准备尚未成功的材料。").foregroundStyle(.secondary)
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
        }.padding(16).font(.system(size:13)).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent))
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
            Text("计划日期不会改变作业截止时间或提醒。").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack{Text("子任务").font(.system(size:13,weight:.semibold));Spacer();Text("\(children.filter{flag($0,"completed")}.count)/\(children.count)").foregroundStyle(.secondary);WorkspaceButton(title:"添加…",identity:"subtask-add"){state.action?("add",identifier(state.task),"","")}.fixedSize().help("添加子任务")}
            if children.isEmpty{Text("拆成几个小步骤，逐项完成。").font(.caption).foregroundStyle(.secondary)}
            ForEach(workspaceRows(children)){row in
                HStack(alignment:.top,spacing:8){
                    Button{state.action?("toggle",identifier(state.task),identifier(row.record),"")}label:{Image(systemName:flag(row.record,"completed") ? "checkmark.circle.fill":"circle").foregroundStyle(flag(row.record,"completed") ? Color(nsColor:AMAppearance.accent):Color.secondary)}.buttonStyle(.plain).accessibilityLabel((flag(row.record,"completed") ? "已完成：":"未完成：")+string(row.record,"title")).accessibilityHint("切换子任务完成状态")
                    VStack(alignment:.leading,spacing:3){Text(string(row.record,"title")).strikethrough(flag(row.record,"completed")).lineLimit(3).help(string(row.record,"title")).fixedSize(horizontal:false,vertical:true);if !string(row.record,"plannedDate").isEmpty{Text(string(row.record,"plannedDate")).font(.caption).foregroundStyle(.secondary)}}.frame(maxWidth:.infinity,alignment:.leading)
                    Menu{Button("编辑名称…"){state.action?("edit",identifier(state.task),identifier(row.record),"")};Button("安排到…"){state.action?("plan",identifier(state.task),identifier(row.record),"")};Button("上移"){state.action?("up",identifier(state.task),identifier(row.record),"")};Button("下移"){state.action?("down",identifier(state.task),identifier(row.record),"")};Divider();Button("删除",role:.destructive){state.action?("delete",identifier(state.task),identifier(row.record),"")}}label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).frame(width:24).help("子任务操作")
                }.padding(.vertical,3)
            }
            if !children.isEmpty && children.allSatisfy({flag($0,"completed")}) && !flag(state.task,"completed"){Label("步骤已全部完成，可以标记整个作业完成。",systemImage:"checkmark.circle").font(.caption).foregroundStyle(.secondary)}
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
        return VStack(alignment:.leading,spacing:8){Text(string(section,"label")).font(.system(size:13,weight:.semibold));Text("\(parents) 项作业 · \(rows.count-parents) 个步骤").font(.caption2).foregroundStyle(.secondary)
            LazyVStack(spacing:8){ForEach(workspaceRows(rows)){row in item(row.record)};if rows.isEmpty{Text("暂无安排").font(.caption).foregroundStyle(.secondary).padding(.vertical,16).frame(maxWidth:.infinity)}}
        }.padding(10).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color(nsColor:AMAppearance.sidebar).opacity(0.55)).clipShape(RoundedRectangle(cornerRadius:10))
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
                Text("安排工作日期，截止时间保持不变。也可以通过“安排到…”操作，无需拖放。").font(.caption).foregroundStyle(.secondary)
                if !state.notice.isEmpty{Text(state.notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}
                ScrollView{
                    if geometry.size.width>=1000{HStack(alignment:.top,spacing:8){ForEach(workspaceRows(Array(state.sections.prefix(7)))){row in section(row.record)}}}
                    else{LazyVStack(spacing:12){ForEach(workspaceRows(Array(state.sections.prefix(7)))){row in section(row.record)}}}
                    ForEach(workspaceRows(Array(state.sections.dropFirst(7)))){row in section(row.record).padding(.top,12)}
                }
            }.padding(4)
        }.background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent))
    }
}
@objc(AMWeeklyPlanningController) public final class AMWeeklyPlanningController:NSViewController {
    private let state=PlanningState()
    @objc public var actionHandler:((String,String,String,String)->Void)? {didSet{state.action=actionHandler}}
    public override func loadView(){view=NSHostingView(rootView:WeeklyPlanningView(state:state))}
    @objc public func updateSections(_ sections:[NSDictionary],notice:String){state.sections=workspaceRecords(sections);state.notice=notice}
}

@MainActor private final class SubmissionHistoryState:ObservableObject {
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
            Text(string(r,"kind")=="submission" || string(r,"kind")=="existing" ? "作业提交":"课程同步／合并").font(.caption)
            Text(string(r,"message")).textSelection(.enabled)
            if !string(r,"commit").isEmpty{WorkspaceSection("提交版本"){Text(string(r,"commit")).font(.system(.caption,design:.monospaced)).textSelection(.enabled);Button("在 GitHub 查看"){state.action?("open",identifier(r))}}}
            WorkspaceSection("操作与核验"){Text("本机操作：\((r["date"] as? Date ?? Date()).formatted())");if let checked=r["checkedAt"] as? Date{Text("最近核验：\(checked.formatted())")};if let confirmed=r["confirmedAt"] as? Date{Text("曾确认推送：\(confirmed.formatted())")};Text("提交记录与作业完成状态分别管理。").foregroundStyle(.secondary)}
            if let review=r["review"] as? NSDictionary {WorkspaceSection("提交前检查"){Text("\((review["date"] as? Date ?? Date()).formatted()) · \((review["count"] as? NSNumber)?.intValue ?? 0) 条建议");Text(string(review,"coverage")=="local" ? "本机检查，用户确认继续":(string(review,"coverage")=="partial" ? "含助手复核；部分未完成，用户确认继续":"含助手复核，用户确认继续")).foregroundStyle(.secondary)}}
            WorkspaceSection("实际文件"){ForEach(r["files"] as? [String] ?? [],id:\.self){Text($0).font(.caption).textSelection(.enabled)}}
            HStack{Button("重新核验"){state.action?("verify",identifier(r))};if string(r,"state") != "confirmed" && !string(r,"commit").isEmpty{Button("核验并重试推送"){state.action?("retry",identifier(r))}}}.disabled(state.busy)
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading)}
    }
    var body:some View {GeometryReader{geo in
        let list=List(selection:Binding(get:{state.selected},set:{state.selected=$0})){ForEach(workspaceRows(state.records)){row in let r=row.record;VStack(alignment:.leading,spacing:5){Text(string(r,"message").isEmpty ? "课程操作":string(r,"message")).lineLimit(2);Text(string(r,"label")).font(.caption).foregroundStyle(string(r,"state")=="confirmed" ? Color.secondary:Color.orange);Text(String(string(r,"commit").prefix(12))).font(.caption2.monospaced())}.padding(.vertical,4).tag(identifier(r))}}.listStyle(.inset)
        VStack(alignment:.leading,spacing:8){HStack{Text("提交记录").font(.headline);Spacer();Button("关联已有提交…"){state.action?("existing","")}.disabled(state.busy)}.padding(.horizontal,12)
            if state.records.isEmpty{VStack(spacing:12){Image(systemName:"clock.arrow.circlepath").font(.largeTitle);Text("暂无提交记录").font(.headline);Text("通过应用提交后，可在这里确认推送状态并回查版本。").foregroundStyle(.secondary)}.frame(maxWidth:.infinity,maxHeight:.infinity)}
            else if geo.size.width<760{VStack(spacing:0){list.frame(height:max(150,geo.size.height*0.4));Divider();if let r=current{details(r)}else{Text("选择一条记录查看详情").foregroundStyle(.secondary).padding()}}}
            else{HStack(spacing:0){list.frame(width:280);Divider();if let r=current{details(r)}else{Text("选择提交记录，查看文件、提交号与推送状态。").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)}}}
        }.background(Color(nsColor:AMAppearance.canvas))
    }}
}
@objc(AMSubmissionHistoryController) @MainActor public final class AMSubmissionHistoryController:NSViewController {
    private let state=SubmissionHistoryState()
    @objc public var actionHandler:((String,String)->Void)? {didSet{state.action=actionHandler}}
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
    @Published var busy=false
    @Published var explicitReference=false
    @Published var reference=Date()
    var courses:[NSDictionary]=[]
    var action:((String,NSDictionary)->Void)?
    var current:NSDictionary? {entries.first{identifier($0)==selected}}
    var snapshot:NSDictionary {["text":text,"entries":entries,"referenceDate":reference,"explicitReference":explicitReference]}
    func send(_ name:String){action?(name,snapshot)}
    func change(_ key:String,_ value:Any){guard let id=selected,let index=entries.firstIndex(where:{identifier($0)==id})else{return};let copy=entries[index].mutableCopy() as! NSMutableDictionary;copy[key]=value;if key != "selected"{copy["edited"]=true;var fields=Set(copy["editedFields"] as? [String] ?? []);fields.insert(key);copy["editedFields"]=Array(fields)};entries[index]=copy.copy() as! NSDictionary;send("draft")}
    func field(_ key:String)->Binding<String>{Binding(get:{self.current.map{string($0,key)} ?? ""},set:{self.change(key,$0)})}
}
private struct QuickEntryView:View {
    @ObservedObject var state:QuickEntryState
    private var rows:some View {
        List(selection:Binding(get:{state.selected},set:{state.selected=$0})){ForEach(workspaceRows(state.entries)){row in let r=row.record
            HStack(alignment:.top){Toggle("",isOn:Binding(get:{flag(r,"selected")},set:{new in state.selected=identifier(r);state.change("selected",new)})).labelsHidden().accessibilityLabel("选择 \(string(r,"title"))");VStack(alignment:.leading,spacing:5){Text(string(r,"title").isEmpty ? "待填写名称":string(r,"title")).lineLimit(2);Text(string(r,"dateText").isEmpty ? "待补全截止时间":string(r,"dateText")).font(.caption).foregroundStyle(.secondary)}}.padding(.vertical,4).tag(identifier(r))
        }}.listStyle(.inset).onCommand(#selector(NSText.selectAll(_:))){for index in state.entries.indices{let copy=state.entries[index].mutableCopy() as! NSMutableDictionary;copy["selected"]=true;state.entries[index]=copy};state.send("draft")}
    }
    private var details:some View {
        ScrollView{VStack(alignment:.leading,spacing:12){if let r=state.current {
            WorkspaceSection("作业信息"){TextField("作业名称",text:state.field("title")).accessibilityIdentifier("quick-title");TextField("课程或分类",text:state.field("subject"));if !state.courses.isEmpty{Menu("关联 GitHub 课程（可选）"){Button("不关联"){state.change("courseRepository","")};ForEach(workspaceRows(state.courses)){row in Button(string(row.record,"name")){state.change("courseRepository",identifier(row.record));state.change("subject",string(row.record,"name"))}}}}}
            WorkspaceSection("截止时间"){TextField("例如 2026-10-20 18:00",text:state.field("dateText")).accessibilityIdentifier("quick-deadline");Text(string(r,"hint")).font(.caption).foregroundStyle(.secondary);Text("时区：\(string(r,"timeZone")) · 消息／录入日期：\((r["referenceDate"] as? Date ?? state.reference).formatted())").font(.caption2).foregroundStyle(.secondary)}
            WorkspaceSection("备注"){TextEditor(text:state.field("notes")).frame(minHeight:90).accessibilityIdentifier("quick-notes");Text("概括和提交要求已预填，可修改或清空。").font(.caption).foregroundStyle(.secondary)}
            WorkspaceSection("提醒"){ForEach([10080,4320,1440,60,0],id:\.self){minutes in let values=(r["reminderOffsets"] as? [NSNumber] ?? []).map(\.intValue);Toggle([10080:"提前7天",4320:"提前3天",1440:"提前1天",60:"提前1小时",0:"到期"][minutes]!,isOn:Binding(get:{values.contains(minutes)},set:{yes in var next=Set(values);if yes{next.insert(minutes)}else{next.remove(minutes)};state.change("reminderOffsets",Array(next).sorted(by:>))}))}}
            DisclosureGroup("查看原文"){Text(string(r,"evidence")).font(.caption).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
        }else{Text("识别后选中一项，在这里核对和修改。").foregroundStyle(.secondary)}}.padding(12)}
    }
    var body:some View {GeometryReader{geo in VStack(alignment:.leading,spacing:12){
        HStack{Text("快速录入作业").font(.title2.bold());Spacer();Button("保存草稿并关闭"){state.send("close")}.keyboardShortcut(.cancelAction)}
        Text("粘贴通知、输入一句话或识别截图；核对后加入安排。").foregroundStyle(.secondary)
        CaptureTextEditor(text:$state.text).frame(height:90).overlay(RoundedRectangle(cornerRadius:6).stroke(Color(nsColor:.separatorColor))).onChange(of:state.text){_ in state.send("draft")}
        HStack{Button("粘贴"){state.send("paste")};Button("选择截图…"){state.send("image")};WorkspaceButton(title:"识别文字",enabled:!state.busy,prominent:true,identity:"quick-parse"){state.send("parse")}.fixedSize();Button("助手识别…"){state.send("skill")};Spacer();if state.busy{ProgressView().controlSize(.small)}}.disabled(state.busy)
        HStack{Toggle("指定消息日期",isOn:$state.explicitReference).onChange(of:state.explicitReference){_ in state.send("draft")};if state.explicitReference{DatePicker("",selection:$state.reference).labelsHidden().onChange(of:state.reference){_ in state.send("draft")}};Spacer()}
        HStack{Button("全选"){for i in state.entries.indices{let copy=state.entries[i].mutableCopy() as! NSMutableDictionary;copy["selected"]=true;state.entries[i]=copy};state.send("draft")};Button("取消选择"){for i in state.entries.indices{let copy=state.entries[i].mutableCopy() as! NSMutableDictionary;copy["selected"]=false;state.entries[i]=copy};state.send("draft")};Text("已选 \(state.entries.filter{flag($0,"selected")}.count) / \(state.entries.count)").foregroundStyle(.secondary);Spacer()}
        if geo.size.width<760{VStack(spacing:0){rows.frame(height:150);Divider();details}}else{HStack(spacing:0){rows.frame(width:260);Divider();details}}
        Divider();Text(state.notice).font(.callout).foregroundStyle(Color(nsColor:.labelColor)).textSelection(.enabled).accessibilityIdentifier("quick-status")
        HStack{Button("手动导入助手结果…"){state.send("import")};Spacer();WorkspaceButton(title:"确认选中作业…",enabled:!state.busy && state.entries.contains{flag($0,"selected")},prominent:true,identity:"quick-save",saveShortcut:true){state.send("save")}.fixedSize()}
    }.padding(16).font(.system(size:13)).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent)).accessibilityElement(children:.contain)}}
}
@objc(AMQuickEntryController) @MainActor public final class AMQuickEntryController:NSViewController {
    private let state=QuickEntryState()
    @objc public var actionHandler:((String,NSDictionary)->Void)? {didSet{state.action=actionHandler}}
    @objc public var snapshot:NSDictionary {state.snapshot}
    @objc public func updateDraft(_ draft:NSDictionary,courses:[NSDictionary],notice:String,busy:Bool){state.text=string(draft,"text");state.entries=workspaceRecords(draft["entries"] as? [NSDictionary] ?? []);state.reference=draft["referenceDate"] as? Date ?? Date();state.explicitReference=flag(draft,"explicitReference");state.courses=workspaceRecords(courses);state.notice=notice;state.busy=busy;if !state.entries.contains(where:{recordIdentifier($0)==state.selected}){state.selected=state.entries.first.map{recordIdentifier($0)}}}
    @objc public func setNotice(_ notice:String,busy:Bool){state.notice=notice;state.busy=busy}
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
    var action:((NSDictionary)->Void)?
    var visible:[NSDictionary]{records.filter{query.isEmpty || string($0,"path").localizedCaseInsensitiveContains(query)}}
    var valid:[NSDictionary]{records.filter{flag($0,"selectable") && selected.contains(string($0,"path"))}}
    var bytes:Int64{valid.reduce(0){$0 + (($1["bytes"] as? NSNumber)?.int64Value ?? 0)}}
    var canStart:Bool{!busy && !valid.isEmpty && valid.count<=256 && bytes<=64*1024*1024}
    var hint:String{valid.count>256 ? "最多256个文件，请减少选择或选择更小的文件夹。":(bytes>64*1024*1024 ? "超过64 MB，请减少选择后分批检查。":(valid.isEmpty ? "请选择至少一个文件。":"只读检查当前文件，不提交或推送。"))}
    func send(_ action:String){self.action?(["action":action,"paths":valid.map{string($0,"path")}] as NSDictionary)}
}
private struct CheckScopeWorkspace:View {
    @ObservedObject var state:CheckScopeState
    private var selection:Binding<String?>{Binding(get:{state.chosen.isEmpty ? nil:state.chosen},set:{state.chosen=$0 ?? ""})}
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            WorkspaceHeading(title:"检查作业文件",subtitle:"1 文件范围  ›  2 检查报告",symbol:"doc.text.magnifyingglass")
            HStack{TextField("搜索文件或目录",text:$state.query).textFieldStyle(.roundedBorder).accessibilityLabel("搜索检查文件");Button("全选当前结果"){for row in state.visible where flag(row,"selectable"){state.selected.insert(string(row,"path"))}}.keyboardShortcut("a",modifiers:.command);Button("取消选择"){state.selected.removeAll()}}.disabled(state.busy)
            ViewThatFits(in:.horizontal){
                HStack(alignment:.top,spacing:16){fileList.frame(minWidth:320);detail.frame(width:260)}
                VStack(alignment:.leading,spacing:12){fileList;detail.frame(height:120)}
            }
            HStack{if state.busy{ProgressView().controlSize(.small)};Text(state.notice).foregroundStyle(.secondary).textSelection(.enabled)}
            HStack{Text("文档 \(state.valid.filter{!flag($0,"image")}.count) · 已选 \(state.valid.count) · 图片 \(state.valid.filter{flag($0,"image")}.count) · 排除 \(state.records.filter{!flag($0,"selectable")}.count)").font(.caption).foregroundStyle(.secondary);Spacer();Text(ByteCountFormatter.string(fromByteCount:state.bytes,countStyle:.file)).font(.caption)}
            Divider()
            HStack{Button(state.busy ? "取消整理":"取消"){state.send("cancel")}.keyboardShortcut(.cancelAction);Text(state.hint).font(.caption).foregroundStyle(state.canStart ? Color.secondary:Color.orange);Spacer();Button("开始检查"){state.send("check")}.buttonStyle(.borderedProminent).disabled(!state.canStart).keyboardShortcut(.defaultAction)}
        }.padding(24).font(.system(size:13)).frame(minWidth:580,minHeight:440).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent))
    }
    private var fileList:some View {
        List(selection:selection){ForEach(state.visible,id:\.self){row in
            let path=string(row,"path")
            HStack(alignment:.top,spacing:8){
                Toggle("包含 \(path)",isOn:Binding(get:{state.selected.contains(path)},set:{if $0{state.selected.insert(path)}else{state.selected.remove(path)}})).labelsHidden().toggleStyle(.checkbox).disabled(!flag(row,"selectable"))
                Image(systemName:flag(row,"selectable") ? (flag(row,"image") ? "photo":"doc.text"):"minus.circle").foregroundStyle(.secondary)
                VStack(alignment:.leading,spacing:3){Text((path as NSString).lastPathComponent).lineLimit(1);Text(string(row,"reason").isEmpty ? ((path as NSString).deletingLastPathComponent.isEmpty ? "作业文件夹":(path as NSString).deletingLastPathComponent):string(row,"reason")).font(.caption).foregroundStyle(.secondary).lineLimit(1)}
            }.help(path).tag(path).padding(.vertical,3)
        }}.listStyle(.inset).scrollContentBackground(.hidden).background(Color(nsColor:AMAppearance.surface)).clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Color(nsColor:AMAppearance.separator),lineWidth:0.5)).accessibilityLabel("检查范围文件清单")
    }
    private var detail:some View {
        VStack(alignment:.leading,spacing:12){Text("范围说明").fontWeight(.semibold);ScrollView{VStack(alignment:.leading,spacing:12){if !state.chosen.isEmpty {Text(state.chosen).textSelection(.enabled);if let row=state.records.first(where:{string($0,"path")==state.chosen}),!string(row,"reason").isEmpty{Text(string(row,"reason")).foregroundStyle(.orange)}};Text("包含子文件夹。Markdown 引用的图片会自动关联、去重。检查边界为本次选择的文件夹；外部图片需要选择共同父目录。");Text("隐藏配置、依赖、缓存、构建目录和敏感文件已排除。排除文件及不支持类型不算检查通过。").foregroundStyle(.secondary)}}}.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color(nsColor:AMAppearance.surface)).clipShape(RoundedRectangle(cornerRadius:10))
    }
}
private struct WorkspaceHeading:View {
    var title:String
    var subtitle:String
    var symbol:String
    var body:some View {HStack(alignment:.center,spacing:12){Image(systemName:symbol).font(.title2).foregroundStyle(Color(nsColor:AMAppearance.accent)).frame(width:32);VStack(alignment:.leading,spacing:4){Text(title).font(.system(size:20,weight:.semibold));Text(subtitle).font(.system(size:12)).foregroundStyle(.secondary)}}}
}
@objc(AMCheckScopeController) @MainActor public final class AMCheckScopeController:NSViewController {
    private let state=CheckScopeState()
    @objc public var actionHandler:((NSDictionary)->Void)?{get{state.action}set{state.action=newValue}}
    public override func loadView(){view=NSHostingView(rootView:CheckScopeWorkspace(state:state))}
    @objc public func update(_ records:[NSDictionary],busy:Bool,notice:String){state.records=records;state.busy=busy;state.notice=notice;if !busy {state.selected=Set(records.filter{flag($0,"selectable")}.map{string($0,"path")})}}
    @objc public func setProgress(_ notice:String){state.notice=notice}
    @objc public var preparing:Bool{state.busy}
    @objc public func requestCheck(){if state.canStart{state.send("check")}}
}

private struct HelpWorkspace:View {
    var action:(String)->Void
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:20){
            WorkspaceHeading(title:"从这里开始",subtitle:"连接课程是可选的；本机录入和文件检查无需登录。",symbol:"sparkles")
            WorkspaceSection("准备好开始了吗？"){HStack{Button("继续配置课程"){action("setup")}.buttonStyle(.borderedProminent);Button("快速录入作业"){action("quick")};Button("查看任务"){action("tasks")};Spacer()}}
            ForEach(Array(zip(["检查新作业","审核作业","检查作业文件","助手识别 · Skill","同步课程文件","提交作业"],["老师有新内容时，在课程页检查；不会合并文件或推送。","核对截止时间和内容后保存；支持全选、批量确认，保存后从审核列表移除。","选中任务，在详情中选择作业文件夹或文件，核对范围后检查。答案和推导可以再交给助手。","准备材料，复制指令给助手；结果自动接回。不会自动发送原文或启动付费分析。","需要更新本机课程资料时使用；会合并老师更新并安全更新个人 fork。","逐项选择提交文件、填写说明，查看提交前检查，只推送个人仓库。"])),id:\.0){title,detail in
                WorkspaceSection(title){VStack(alignment:.leading,spacing:10){Text(detail).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true);if title=="审核作业"{Button("打开待审核作业"){action("review")}}else if title=="检查作业文件"{Button("选择任务开始检查"){action("tasks")}}else if title=="助手识别 · Skill"{Button("查看识别批次"){action("skill")}}else{Button("打开课程"){action("courses")}}}}
            }
            Text("本机检查不证明答案正确。检查、同步和提交是不同操作；完成任务也不等于代码已推送。").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth:900,alignment:.leading).frame(maxWidth:.infinity,alignment:.leading)}.font(.system(size:13)).background(Color(nsColor:AMAppearance.canvas)).tint(Color(nsColor:AMAppearance.accent))
    }
}
@objc(AMHelpController) @MainActor public final class AMHelpController:NSViewController {
    @objc public var actionHandler:((String)->Void)?
    public override func loadView(){view=NSHostingView(rootView:HelpWorkspace(action:{[weak self] in self?.actionHandler?($0)}))}
}

private final class WorkspaceHintState:ObservableObject {@Published var dismissed=false}
private struct WorkspaceHint:View {
    let key:String
    let text:String
    @StateObject private var hint=WorkspaceHintState()
    private var stored:Bool{!ProcessInfo.processInfo.arguments.contains("--preview") && UserDefaults.standard.bool(forKey:"am.hint18."+key)}
    var body:some View {if !hint.dismissed && !stored {HStack(alignment:.top,spacing:10){Image(systemName:"info.circle").foregroundStyle(Color(nsColor:AMAppearance.accent));Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true);Spacer(minLength:4);Button{hint.dismissed=true;if !ProcessInfo.processInfo.arguments.contains("--preview"){UserDefaults.standard.set(true,forKey:"am.hint18."+key)}}label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel("关闭本条使用提示")}.padding(12).background(Color(nsColor:AMAppearance.surface)).clipShape(RoundedRectangle(cornerRadius:8))}}
}
