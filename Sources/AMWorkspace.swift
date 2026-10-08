import AppKit
import SwiftUI

private func string(_ record: NSDictionary, _ key: String) -> String { record[key] as? String ?? "" }
private func flag(_ record: NSDictionary, _ key: String) -> Bool { (record[key] as? NSNumber)?.boolValue ?? false }
private func identifier(_ record: NSDictionary) -> String { string(record, "id") }

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
    @Published var leadDays = 0
    @Published var personalDate = Date()
    @Published var customPersonalDate = false
    @Published var reminders = true
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
        self.records = records
        checked.formIntersection(Set(records.map(identifier)))
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
        notes = task?["notes"] as? String ?? [string(record,"summary"),string(record,"submissionRequirements")].filter{!$0.isEmpty}.joined(separator:"\n\n")
        if notes.isEmpty { notes = string(record,"snippet") }
        if let value = record["due"] as? Date { date = value; hasDate = true }
        else if let value = task?["announcedDue"] as? Date { date = value; hasDate = true }
        else if let value = record["dateOnly"] as? String {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(identifier:string(record,"timeZone")) ?? .current
            date = formatter.date(from:value) ?? Date(); hasDate = false
        } else { date = Date(); hasDate = false }
        dateConfirmed = hasDate && !flag(record,"needsDate") && !flag(record,"needsTime") && (record["warnings"] as? [String] ?? []).isEmpty
        leadDays = (task?["leadDays"] as? NSNumber)?.intValue ?? 0
        customPersonalDate = leadDays < 0
        personalDate = task?["due"] as? Date ?? date
        reminders = ((task?["reminderOffsets"] as? [NSNumber])?.isEmpty == false) || task == nil
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
        let due = editing ? (hasDate && dateConfirmed ? date : nil) : record["due"] as? Date
        guard let due, !(editing ? title : string(record,"suggestedTitle")).trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }
        if !editing && (flag(record,"needsDate") || flag(record,"needsTime") || !(record["warnings"] as? [String] ?? []).isEmpty || flag(record,"relative") || flag(record,"modelOnly")) { return nil }
        let savedTitle=(record["existingTask"] as? NSDictionary)?["title"] as? String
        var draft: [String:Any] = ["title": editing ? title : (savedTitle ?? (string(record,"suggestedTitle").isEmpty ? string(record,"title") : string(record,"suggestedTitle"))),"teacherDue":due,"dateConfirmed":true]
        if editing {
            draft["notes"] = notes; draft["leadDays"] = customPersonalDate ? -1 : max(0,leadDays)
            if customPersonalDate { draft["personalDue"] = personalDate }
            let old = (record["existingTask"] as? NSDictionary)?["reminderOffsets"] as? [NSNumber]
            draft["reminderOffsets"] = reminders ? (old?.isEmpty == false ? old! : [1440,60,0] as [NSNumber]) : [NSNumber]()
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
        else {activeRecord=nil;selected=""}
        if advance {
            if let next=visible.first(where:{identifier($0) != previous}) { load(next) }
            else { activeRecord=nil; selected="" }
        }
        return true
    }
    func saveChecked() {
        guard !paused, resolve() else { return }
        let targets=visible.filter{checked.contains(identifier($0))}
        let payloads=targets.compactMap{payload($0,editing:false)}
        guard !payloads.isEmpty else { message="所选作业需要逐项补全或确认日期。"; return }
        let alert=NSAlert(); alert.messageText="确认加入 \(payloads.count) 项作业？"
        let formatter=DateFormatter(); formatter.dateFormat="yyyy-MM-dd HH:mm z"
        alert.informativeText=payloads.map { item in
            let record=item["record"] as! NSDictionary, draft=item["draft"] as! NSDictionary
            return "\(string(record,"repository")) · \(string(draft,"title"))\n\(formatter.string(from:draft["teacherDue"] as! Date))"
        }.joined(separator:"\n\n") + (payloads.count < targets.count ? "\n\n其余 \(targets.count-payloads.count) 项仍待补全。" : "")
        alert.addButton(withTitle:"确认加入"); alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let result=save?(payloads) ?? "保存接口不可用。"
        message=result.isEmpty ? "已加入 \(payloads.count) 项；未完成的条目继续待审核。" : result
        if result.isEmpty { checked.subtract(targets.map(identifier)) }
    }
}

private struct ReviewWorkspace: View {
    @ObservedObject var state: ReviewState
    @FocusState private var searchFocused:Bool
    private func editing<T>(_ key: ReferenceWritableKeyPath<ReviewState,T>) -> Binding<T> {
        Binding(get:{state[keyPath:key]},set:{state[keyPath:key]=$0; state.dirty=true})
    }
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
                        ForEach(state.visible,id:\.self) { record in
                            HStack(alignment:.top,spacing:8) {
                                Toggle("选择",isOn:Binding(get:{state.checked.contains(identifier(record))},set:{if $0 {state.checked.insert(identifier(record))}else{state.checked.remove(identifier(record))}})).labelsHidden().toggleStyle(.checkbox).accessibilityLabel("选择\(string(record,"title"))")
                                Button { state.select(record) } label: {
                                    VStack(alignment:.leading,spacing:5) {
                                        Text(string(record,"suggestedTitle").isEmpty ? string(record,"title") : string(record,"suggestedTitle")).font(.system(size:13,weight:.medium)).lineLimit(2)
                                        Text(string(record,"repository")).font(.caption).foregroundStyle(.secondary)
                                        Label(record["existingTask"] == nil ? "新作业" : "更新建议",systemImage:record["existingTask"] == nil ? "tray" : "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth:.infinity,alignment:.leading).padding(8).background(state.selected == identifier(record) ? Color.accentColor.opacity(0.12) : Color.clear).cornerRadius(8)
                                }.buttonStyle(.plain)
                            }.padding(.horizontal,4)
                        }
                    }.padding(.vertical,4)
                }.frame(minWidth:220,idealWidth:280,maxWidth:340)
                ScrollView {
                    if let record=state.current {
                        VStack(alignment:.leading,spacing:16) {
                            Text(record["existingTask"] == nil ? "审核作业" : "审核更新").font(.title3.bold())
                            if string(record,"reviewStatus")=="已导入" {Text("此版本已加入任务，可在任务页继续编辑。").foregroundStyle(.secondary)}
                            TextField("作业名称",text:editing(\.title)).textFieldStyle(.roundedBorder)
                            GroupBox("截止时间") {
                                VStack(alignment:.leading,spacing:10) {
                                    Text(string(record,"dateText").isEmpty ? "老师未说明完整截止时间" : "老师原文：\(string(record,"dateText"))").textSelection(.enabled)
                                    if let warnings=record["warnings"] as? [String] { ForEach(warnings,id:\.self){Text($0).foregroundStyle(.orange)} }
                                    if let due=record["suggestedDue"] as? Date {
                                        Text("建议：\(due.formatted(date:.abbreviated,time:.shortened))")
                                        if let basis=record["dateBasis"] as? NSDictionary, let date=basis["date"] as? Date { Text("依据：\(date.formatted()) · \(String(string(basis,"commit").prefix(7)))").font(.caption).foregroundStyle(.secondary) }
                                        Button("采用此建议"){state.date=due;state.hasDate=true;state.dateConfirmed=true;state.dirty=true}
                                    }
                                    Toggle("填写完整截止日期与时间",isOn:editing(\.hasDate))
                                    if state.hasDate {
                                        DatePicker("老师截止时间",selection:editing(\.date),displayedComponents:[.date,.hourAndMinute])
                                        Toggle("已核对日期与时间",isOn:editing(\.dateConfirmed))
                                    }
                                    Toggle("单独设置我的 DDL",isOn:editing(\.customPersonalDate))
                                    if state.customPersonalDate { DatePicker("我的 DDL",selection:editing(\.personalDate),displayedComponents:[.date,.hourAndMinute]) }
                                    else { Stepper("我的 DDL 提前 \(max(0,state.leadDays)) 天",value:editing(\.leadDays),in:0...365) }
                                    Text("课程时区：\(string(record,"timeZone"))").font(.caption).foregroundStyle(.secondary)
                                    Toggle("启用提醒",isOn:editing(\.reminders))
                                }.frame(maxWidth:.infinity,alignment:.leading).padding(4)
                                .environment(\.timeZone,TimeZone(identifier:string(record,"timeZone")) ?? .current)
                            }
                            VStack(alignment:.leading,spacing:6) { Text("内容与备注").fontWeight(.medium); TextEditor(text:editing(\.notes)).frame(minHeight:120).overlay(RoundedRectangle(cornerRadius:6).stroke(Color.secondary.opacity(0.2))) }
                            GroupBox("老师原文与来源") {
                                VStack(alignment:.leading,spacing:8) {
                                    Text("\(string(record,"repository")) / \(string(record,"path")):\((record["line"] as? NSNumber)?.intValue ?? 1)").font(.caption).foregroundStyle(.secondary)
                                    Text(string(record,"snippet")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                                    if let attachments=record["attachments"] as? [NSDictionary] { ForEach(attachments,id:\.self){Text("附件：\(string($0,"path"))\n\(string($0,"snippet"))").textSelection(.enabled)} }
                                }.padding(4)
                            }
                        }.padding(.horizontal,16).padding(.vertical,8).disabled(string(record,"reviewStatus")=="已导入")
                    } else {
                        VStack(spacing:12){Image(systemName:"tray").font(.largeTitle).foregroundStyle(.secondary);Text("暂无待审核作业");Text("检查课程后，需确认的作业会显示在这里。").foregroundStyle(.secondary)}.frame(maxWidth:.infinity,minHeight:240)
                    }
                }.frame(minWidth:300)
            }
            HStack {
                Text(state.message.isEmpty ? (state.dirty ? "有未保存修改" : "核对原文后保存；明确日期可批量确认") : state.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("保存并下一项"){state.saveCurrent(advance:true)}.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return,modifiers:.command).disabled(state.current == nil || state.paused || string(state.current ?? [:],"reviewStatus")=="已导入")
            }
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
                DisclosureGroup("高级设置") {Button("GitHub App 公开配置…"){state.action?("advanced")}.padding(.top,8)}
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
    var current:NSDictionary? {records.first{identifier($0)==selected}}
    func update(_ records:[NSDictionary], selected:String, information:String, empty:String, paused:Bool) {
        self.records=records;self.selected=selected.isEmpty ? nil:selected;self.information=information;self.empty=empty;self.paused=paused
    }
}
private struct CourseWorkspace:View {
    @ObservedObject var state:CourseState
    private func kind(_ record:NSDictionary)->String {flag(record,"confirmed") ? "已加入任务" : ["assignment":"作业","exam":"考试","classroom":"课上任务","unknown":"待确认类型"][string(record,"kind")] ?? "作业"}
    private var entries:some View {
        List(selection:Binding(get:{state.selected},set:{state.selected=$0;if let id=$0 {state.action?("select",id)}})) {
            ForEach(state.records.indices,id:\.self) { index in
                let record=state.records[index]
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
                else if let record=state.current {
                    Text(string(record,"suggestedTitle").isEmpty ? string(record,"title") : string(record,"suggestedTitle")).font(.title3.bold())
                    Label(kind(record),systemImage:string(record,"kind")=="exam" ? "doc.text" : "checklist").foregroundStyle(.secondary)
                    if let due=record["due"] as? Date {Text("截止：\(due.formatted(date:.abbreviated,time:.shortened))")}
                    if !string(record,"dateText").isEmpty {Text("老师截止原文：\(string(record,"dateText"))").textSelection(.enabled)}
                    if !string(record,"summary").isEmpty {GroupBox("内容概括"){Text(string(record,"summary")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
                    if !string(record,"submissionRequirements").isEmpty {GroupBox("提交要求"){Text(string(record,"submissionRequirements")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
                    Text("\(string(record,"repository")) · \(string(record,"path"))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        if flag(record,"confirmed") || string(record,"kind").isEmpty || string(record,"kind")=="assignment" {Button(flag(record,"confirmed") ? "编辑任务…":"审核作业…"){state.action?("review",identifier(record))}.buttonStyle(.borderedProminent).disabled(state.paused)}
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
    var body:some View {
        GeometryReader { geometry in
            if state.records.isEmpty {details}
            else if geometry.size.width<760 {VSplitView{entries.frame(minHeight:160,idealHeight:220);details.frame(minHeight:180)}}
            else {HSplitView{entries.frame(idealWidth:300,maxWidth:360);details}}
        }.font(.system(size:13)).background(Color(nsColor:.windowBackgroundColor)).tint(.blue)
    }
}
@objc(AMCourseController)
@MainActor public final class AMCourseController:NSViewController {
    private let state=CourseState()
    @objc public var actionHandler:((String,String)->Void)? {get{state.action}set{state.action=newValue}}
    @objc public func updateRecords(_ records:[NSDictionary],selected:String,information:String,empty:String,paused:Bool){state.update(records,selected:selected,information:information,empty:empty,paused:paused)}
    private func scrollViews(_ view:NSView)->[NSScrollView] {var result:[NSScrollView]=[];if let scroll=view as? NSScrollView {result.append(scroll)};for child in view.subviews {result+=scrollViews(child)};return result}
    @objc public func scrollPositions()->[NSValue] {scrollViews(view).map{NSValue(point:$0.contentView.bounds.origin)}}
    @objc public func restoreScrollPositions(_ positions:[NSValue]) {DispatchQueue.main.async {for (scroll,value) in zip(self.scrollViews(self.view),positions){scroll.contentView.scroll(to:value.pointValue);scroll.reflectScrolledClipView(scroll.contentView)}}}
    public override func loadView(){view=NSHostingView(rootView:CourseWorkspace(state:state))}
}
