import AppKit
import SwiftUI

private func string(_ record: NSDictionary, _ key: String) -> String { record[key] as? String ?? "" }
private func flag(_ record: NSDictionary, _ key: String) -> Bool { (record[key] as? NSNumber)?.boolValue ?? false }
private func identifier(_ record: NSDictionary) -> String { string(record, "id") }

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

@MainActor
final class ReviewState: ObservableObject {
    @Published var records: [NSDictionary] = []
    @Published var selected = ""
    @Published var checked: Set<String> = []
    @Published var query = ""
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
    @Published var paused = false
    var activeRecord: NSDictionary?
    var save: (([NSDictionary]) -> String)?
    var originalTitle = "", originalNotes = ""
    var current: NSDictionary? { activeRecord }
    var visible: [NSDictionary] {
        records.filter { query.isEmpty || [string($0,"suggestedTitle"),string($0,"title"),string($0,"repository"),string($0,"path")].joined(separator:" ").localizedCaseInsensitiveContains(query) }
    }
    func refresh(_ records: [NSDictionary]) {
        let records = workspaceRecords(records)
        self.records = records
        checked.formIntersection(Set(records.filter{string($0,"reviewStatus") != "已导入"}.map(identifier)))
        if !dirty {
            if let record = records.first(where: {identifier($0) == selected}) { load(record) }
            else if let first = records.first { load(first) }
            else { selected = ""; activeRecord = nil }
        }
    }
    func load(_ record: NSDictionary) {
        activeRecord = record; selected = identifier(record)
        let task = record["existingTask"] as? NSDictionary
        title = task?["title"] as? String ?? (string(record,"suggestedTitle").isEmpty ? string(record,"title") : string(record,"suggestedTitle"))
        notes = task?["notes"] as? String ?? ""
        let basis = record["dateBasis"] as? NSDictionary
        let suggestion = !flag(record,"needsTime") && (record["warnings"] as? [String] ?? []).isEmpty && basis?["date"] is Date && !string(basis ?? [:],"commit").isEmpty ? record["suggestedDue"] as? Date : nil
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
    func select(_ record: NSDictionary) { guard identifier(record) != selected, resolve() else { return }; load(record) }
    func payload(_ record: NSDictionary, editing: Bool) -> NSDictionary? {
        let due = editing ? (hasDate && dateConfirmed ? date : nil) : ((record["existingTask"] as? NSDictionary)?["due"] as? Date ?? record["due"] as? Date)
        let proposedTitle=string(record,"suggestedTitle").isEmpty ? string(record,"title"):string(record,"suggestedTitle")
        guard let due, !(editing ? title : proposedTitle).trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }
        if !editing && (flag(record,"needsDate") || flag(record,"needsTime") || !(record["warnings"] as? [String] ?? []).isEmpty || flag(record,"relative") || flag(record,"modelOnly")) { return nil }
        let savedTitle=(record["existingTask"] as? NSDictionary)?["title"] as? String
        var draft: [String:Any] = ["title": editing ? title : (savedTitle ?? proposedTitle),"assignmentDue":due,"dateConfirmed":true]
        if editing {
            draft["notes"] = notes
            draft["reminderOffsets"] = reminders ? reminderOffsets.sorted(by:>) : [Int]()
        }
        return ["record":record,"draft":draft] as NSDictionary
    }
    @discardableResult func saveCurrent(advance:Bool) -> Bool {
        guard !paused, let record=current, let payload=payload(record,editing:true) else { message = "请补全并确认完整截止日期和时间。"; return false }
        let previous = selected
        let result = save?([payload]) ?? "保存接口不可用。"
        guard result.isEmpty else { message=result; return false }
        dirty=false; message="已保存，日历和提醒已同步。"
        if let refreshed=records.first(where:{identifier($0)==previous}) {load(refreshed)}
        else if let next=visible.first {load(next)}
        else {activeRecord=nil;selected=""}
        if advance {
            if let next=visible.first(where:{identifier($0) != previous && string($0,"reviewStatus") != "已导入"}) { load(next) }
            else { activeRecord=nil; selected="" }
        }
        return true
    }
    func saveChecked() {
        guard !paused, resolve() else { return }
        let targets=visible.filter{checked.contains(identifier($0)) && string($0,"reviewStatus") != "已导入"}
        let payloads=targets.compactMap{payload($0,editing:false)}
        guard !payloads.isEmpty else { message="所选作业需要逐项补全或确认日期。"; return }
        let alert=NSAlert(); alert.messageText="确认加入 \(payloads.count) 项作业？"
        let formatter=DateFormatter(); formatter.dateFormat="yyyy-MM-dd HH:mm z"
        alert.informativeText=payloads.map { item in
            let record=item["record"] as! NSDictionary, draft=item["draft"] as! NSDictionary
            return "\(string(record,"repository")) · \(string(draft,"title"))\n\(formatter.string(from:draft["assignmentDue"] as! Date))"
        }.joined(separator:"\n\n") + (payloads.count < targets.count ? "\n\n其余 \(targets.count-payloads.count) 项仍待补全。" : "")
        alert.addButton(withTitle:"确认加入"); alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let result=save?(payloads) ?? "保存接口不可用。"
        message=result.isEmpty ? "已加入 \(payloads.count) 项；未完成的条目继续待审核。" : result
        if result.isEmpty { checked.subtract(targets.map(identifier)) }
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
            GroupBox("截止时间") {
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
            VStack(alignment:.leading,spacing:6) { Text("我的备注（选填）").fontWeight(.medium); TextEditor(text:editing(\.notes)).frame(minHeight:100).overlay(RoundedRectangle(cornerRadius:6).stroke(Color.secondary.opacity(0.2))) }
            if !string(record,"summary").isEmpty {GroupBox("作业内容"){Text(string(record,"summary")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
            if !string(record,"submissionRequirements").isEmpty {GroupBox("提交要求"){Text(string(record,"submissionRequirements")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
            GroupBox("老师原文与来源") {
                VStack(alignment:.leading,spacing:8) {
                    Text("\(string(record,"repository")) / \(string(record,"path")):\((record["line"] as? NSNumber)?.intValue ?? 1)").font(.caption).foregroundStyle(.secondary)
                    Text(string(record,"snippet")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    if let attachments=record["attachments"] as? [NSDictionary] { ForEach(workspaceRows(attachments,key:"path")){Text("附件：\(string($0.record,"path"))\n\(string($0.record,"snippet"))").textSelection(.enabled)} }
                }.padding(4)
            }
        }.padding(.horizontal,16).padding(.vertical,8)
    }
}
private struct ReviewSaveBar:View {
    @ObservedObject var state:ReviewState
    let advance:Bool
    var body:some View {
        HStack {
            Text(state.message.isEmpty ? (state.dirty ? "有未保存修改" : "核对后保存；已审核内容可继续编辑") : state.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            Button(advance ? "保存并下一项" : (state.current?["existingTask"] == nil ? "确认作业":"保存修改")){state.saveCurrent(advance:advance)}.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return,modifiers:.command).disabled(state.current == nil || state.paused)
        }
    }
}
private struct ReviewWorkspace: View {
    @ObservedObject var state: ReviewState
    @FocusState private var searchFocused:Bool
    var body: some View {
        VStack(spacing:12) {
            HStack {
                TextField("搜索名称、课程或文件",text:$state.query).textFieldStyle(.roundedBorder).focused($searchFocused)
                Text("\(state.visible.count) 项").foregroundStyle(.secondary)
                Button("确认所选 \(state.checked.count) 项"){state.saveChecked()}.disabled(state.checked.isEmpty || state.paused)
            }
            HSplitView {
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
                                        Label(string(record,"reviewStatus")=="已导入" ? "已审核" : (record["existingTask"] == nil ? "新作业" : "更新建议"),systemImage:string(record,"reviewStatus")=="已导入" ? "checkmark.circle" : (record["existingTask"] == nil ? "tray" : "arrow.triangle.2.circlepath")).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth:.infinity,alignment:.leading).padding(8).background(state.selected == identifier(record) ? Color.accentColor.opacity(0.12) : Color.clear).cornerRadius(8)
                                }.buttonStyle(.plain)
                            }.padding(.horizontal,4)
                        }
                    }.padding(.vertical,4)
                }.frame(minWidth:220,idealWidth:280,maxWidth:340)
                ScrollView {
                    if let record=state.current {
                        ReviewDetails(state:state,record:record)
                    } else {
                        VStack(spacing:12){Image(systemName:"tray").font(.largeTitle).foregroundStyle(.secondary);Text("暂无待审核作业");Text("检查课程后，需确认的作业会显示在这里。").foregroundStyle(.secondary)}.frame(maxWidth:.infinity,minHeight:240)
                    }
                }.frame(minWidth:300)
            }
            ReviewSaveBar(state:state,advance:true)
        }.padding(12).font(.system(size:13)).tint(.blue).onChange(of:state.searchToken){_ in searchFocused=true}
    }
}

@objc(AMReviewController)
@MainActor public final class AMReviewController: NSViewController {
    private let state=ReviewState()
    @objc public var saveHandler: (([NSDictionary]) -> String)? { get{state.save} set{state.save=newValue} }
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
                GroupBox("作业识别") {
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
                        Toggle("自动加入完整明确日期的新作业",isOn:binding(\.automatic))
                        Text("相对日期、缺失时间和考试不会自动加入；已有任务更新仍需审核。").foregroundStyle(.secondary)
                        Button("保存识别设置"){_ = state.persist()}.buttonStyle(.borderedProminent).disabled(state.localBusy)
                        if !state.message.isEmpty {Text(state.message).textSelection(.enabled)}
                    }.padding(8).frame(maxWidth:.infinity,alignment:.leading)
                }
                GroupBox("账户与提醒") {HStack{Button("GitHub 账户…"){state.action?("account")};Button("提醒设置与测试…"){state.action?("notifications")};Spacer()}.padding(8)}
                GroupBox("软件更新") {HStack{Button("检查更新…"){state.action?("check-update")};Button("自动检查设置…"){state.action?("updates")};Spacer()}.padding(8)}
                GroupBox("可选 Skill") {VStack(alignment:.leading,spacing:8){Text("一次勾选多门课程，导出一个材料包交给助手分析，再一次导入结果。默认仅处理新增或变化文档。");HStack{Button("交给助手识别…"){state.action?("skill-export")};Button("导入助手结果…"){state.action?("skill-import")}};Text("默认手动运行，不直接修改任务或执行 Git。").foregroundStyle(.secondary)}.padding(8)}
                DisclosureGroup("高级设置") {Button("GitHub 登录与兼容设置…"){state.action?("advanced")}.padding(.top,8)}
                HStack{Spacer();Button("完成"){state.action?("close")}.keyboardShortcut(.cancelAction)}
            }.padding(24)
        }.onChange(of:state.mode){state.changeMode($0)}.font(.system(size:13)).frame(minWidth:540,minHeight:520).background(Color(nsColor:.windowBackgroundColor)).tint(.blue)
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
        self.records=workspaceRecords(records);self.information=information;self.empty=empty;self.paused=paused;review.paused=paused
        // Background refresh retains an unfinished draft. Navigation resolves it first.
        if !review.dirty {self.selected=selected.isEmpty ? nil:selected;draftRow=records.first{identifier($0)==self.selected}}
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
    private func kind(_ record:NSDictionary)->String {flag(record,"confirmed") || string(record,"reviewStatus")=="已导入" ? "已审核" : string(record,"reviewStatus")=="有更新" ? "有更新，待审核" : ["assignment":"作业","exam":"考试","classroom":"课上任务","unknown":"待确认类型"][string(record,"kind")] ?? "作业"}
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
                else if let record=state.current, state.reviewRecord(record) != nil {
                    if state.review.dirty && !state.records.contains(where:{identifier($0)==state.selected}) {Text("当前作业不在筛选结果中；未保存的内容保留。").foregroundStyle(.orange)}
                    HStack{Label(kind(record),systemImage:"checklist");Spacer();if !flag(record,"confirmed"){Button("更改类型…"){state.action?("type",identifier(record))}.disabled(state.paused)}}
                    CourseReviewPane(state:state.review)
                } else if let record=state.current {
                    Text(string(record,"suggestedTitle").isEmpty ? string(record,"title") : string(record,"suggestedTitle")).font(.title3.bold())
                    Label(kind(record),systemImage:string(record,"kind")=="exam" ? "doc.text" : "checklist").foregroundStyle(.secondary)
                    if let due=record["due"] as? Date {Text("截止：\(due.formatted(date:.abbreviated,time:.shortened))")}
                    if !string(record,"notes").isEmpty {GroupBox("我的备注"){Text(string(record,"notes")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
                    if !string(record,"dateText").isEmpty {Text("老师截止原文：\(string(record,"dateText"))").textSelection(.enabled)}
                    if !string(record,"summary").isEmpty {GroupBox("内容概括"){Text(string(record,"summary")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
                    if !string(record,"submissionRequirements").isEmpty {GroupBox("提交要求"){Text(string(record,"submissionRequirements")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
                    Text("\(string(record,"repository")) · \(string(record,"path"))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        if !flag(record,"confirmed"){Button("更改类型…"){state.action?("type",identifier(record))}.disabled(state.paused)}
                    }
                    Divider()
                    Text("老师原文").font(.headline)
                    ForEach(Array((record["documents"] as? [NSDictionary] ?? [record]).enumerated()),id:\.offset) { _, document in
                        VStack(alignment:.leading,spacing:8){Text(string(document,"path")).font(.caption).foregroundStyle(.secondary);Text(string(document,"snippet").isEmpty ? string(document,"notes"):string(document,"snippet")).textSelection(.enabled)}
                    }
                } else {VStack(alignment:.leading,spacing:12){Label(state.empty.isEmpty ? "选择课程内容查看详情":state.empty,systemImage:"tray");Text("检查只读取老师内容；同步文件与提交作业是独立操作。").foregroundStyle(.secondary)}}
            }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
        }.frame(minWidth:260)
    }
    private var detailPane:some View {
        VStack(spacing:0){details;if let record=state.current,state.reviewRecord(record) != nil {Divider();ReviewSaveBar(state:state.review,advance:false).padding(12)}}
    }
    var body:some View {
        GeometryReader { geometry in
            if state.records.isEmpty {detailPane}
            else if geometry.size.width<760 {VSplitView{entries.frame(minHeight:160,idealHeight:220);detailPane.frame(minHeight:180)}}
            else {HSplitView{entries.frame(idealWidth:300,maxWidth:360);detailPane}}
        }.font(.system(size:13)).background(Color(nsColor:.windowBackgroundColor)).tint(.blue)
    }
}
@objc(AMCourseController)
@MainActor public final class AMCourseController:NSViewController {
    private let state=CourseState()
    @objc public var actionHandler:((String,String)->Void)? {get{state.action}set{state.action=newValue}}
    @objc public var saveHandler:(([NSDictionary])->String)? {get{state.review.save}set{state.review.save=newValue}}
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
                    HStack(spacing:5){Image(systemName:index < state.step ? "checkmark.circle.fill":"\(index+1).circle");Text(steps[index]).font(.caption)}.foregroundStyle(index==state.step ? Color.accentColor:Color.secondary)
                    if index<3 {Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)}
                }}.accessibilityLabel("第 \(state.step+1) 步，共四步")
                Divider()
            }
            Text(state.step < 4 ? steps[max(0,min(3,state.step))]:"开始使用 AM Helper").font(.title2.weight(.semibold))
            content
            if state.busy {HStack{ProgressView().controlSize(.small);Text(state.step==0 ? "正在等待登录，其他课程数据会保留。":"正在逐门处理，成功结果会保留。").foregroundStyle(.secondary)}}
            Text(state.message).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Divider()
            footer
        }.padding(24).frame(minWidth:620,minHeight:450).font(.system(size:13)).background(Color(nsColor:.windowBackgroundColor))
    }
    @ViewBuilder private var content:some View {
        if state.step==0 {
            ScrollView {VStack(alignment:.leading,spacing:16){
                Label("用浏览器连接 GitHub，无需 SSH 或额外安装工具。",systemImage:"person.crop.circle.badge.checkmark")
                Text(official ? "授权页面会显示 GitHub CLI，这是软件内置的 GitHub 官方登录工具。它申请 repo、read:org、gist 权限，范围比所选课程更宽；本应用仅处理你选择的课程，登录令牌只保存在这台 Mac 的钥匙串。":"你在高级设置中选择了旧兼容登录，不使用内置官方工具。旧 OAuth 可能受组织应用限制，旧 GitHub App 需单独安装授权及本机上游凭据。登录令牌只存本机。").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
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
            Button(state.busy && state.step==0 ? "取消登录":(state.step==4 ? "跳过提示":"下次继续")){state.send("close")}.keyboardShortcut(.cancelAction).disabled(state.busy && state.step != 0)
            if state.step>0 && state.step<4 {Button("返回"){state.send("back")}.disabled(state.busy)}
            Spacer()
            if state.step==0 {Button("浏览器登录"){state.send("login")}.disabled(state.busy || !string(state.context,"code").isEmpty).keyboardShortcut(.defaultAction)}
            else if state.step==1 {Button("下一步：核验课程"){state.send("select")}.disabled(state.busy || state.selected.isEmpty).keyboardShortcut(.defaultAction)}
            else if state.step==2 {Button("关联选定目录"){state.send("link")}.disabled(state.busy);Button("下一步：首次检查"){state.send("check")}.disabled(state.busy || !state.records.contains{flag($0,"ready")}).keyboardShortcut(.defaultAction)}
            else if state.step==3 {Button("重新检查就绪课程"){state.send("check")}.disabled(state.busy);Button("完成并查看使用提示"){state.send("finish")}.disabled(state.busy).keyboardShortcut(.defaultAction)}
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
