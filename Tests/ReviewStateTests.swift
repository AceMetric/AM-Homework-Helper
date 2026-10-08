import Foundation

@main struct ReviewStateTests {
    @MainActor static func main() {
        var count=0
        func check(_ pass:Bool,_ label:String){count += 1;if !pass {fatalError(label)}}
        let record:[String:Any]=["id":"source-1","title":"作业","suggestedTitle":"报告","repository":"teacher/course","path":"homework.md","blobSHA":"v1","kind":"assignment","due":Date(timeIntervalSince1970:2_000_000_000),"needsDate":false,"needsTime":false,"summary":"内容摘要"]
        let state=ReviewState();state.refresh([record as NSDictionary])
        check(state.title=="报告" && state.hasDate && state.dateConfirmed,"initial complete proposal")
        state.notes="自己的备注";state.dirty=true;var newer=record;newer["blobSHA"]="v2";state.refresh([newer as NSDictionary])
        check(state.notes=="自己的备注" && state.current?["blobSHA"] as? String=="v1","background refresh preserves draft and version")
        state.save={_ in "存储失败"};check(!state.saveCurrent(advance:true) && state.dirty,"save failure preserves inputs")
        var captured:[NSDictionary]=[];state.save={items in captured=items;state.refresh([]);return ""}
        check(state.saveCurrent(advance:true) && !state.dirty && state.current==nil,"successful save advances without reopening a sheet")
        check(captured.count==1 && (captured[0]["draft"] as? NSDictionary)?["notes"] as? String=="自己的备注","save uses edited draft")
        state.refresh([record as NSDictionary]);state.dateConfirmed=false;check(state.payload(record as NSDictionary,editing:true)==nil,"unconfirmed manual date blocks save")
        var ambiguous=record;ambiguous["needsTime"]=true;ambiguous.removeValue(forKey:"due");state.refresh([ambiguous as NSDictionary]);check(!state.hasDate && !state.dateConfirmed,"missing time not silently filled")
        check(state.payload(ambiguous as NSDictionary,editing:false)==nil,"batch cannot adopt incomplete deadline")
        var relative=record;relative["relative"]=true;check(state.payload(relative as NSDictionary,editing:false)==nil,"batch cannot silently adopt relative suggestion")
        state.checked=["source-1","removed"];state.refresh([record as NSDictionary]);check(state.checked==["source-1"],"refresh removes stale checked ids")
        state.query="nothing";check(state.visible.isEmpty,"filter stays local to review state");state.query="报告";check(state.visible.count==1,"search includes suggested title")
        var updated=record;updated["existingTask"]=["title":"手动标题","notes":"手动备注","leadDays":-1,"due":Date(timeIntervalSince1970:1_900_000_000)] as NSDictionary
        check((state.payload(updated as NSDictionary,editing:false)?["draft"] as? NSDictionary)?["title"] as? String=="手动标题","batch update preserves user title")
        state.refresh([updated as NSDictionary]);check(state.date==Date(timeIntervalSince1970:1_900_000_000) && state.dateConfirmed,"existing deadline remains canonical even with legacy lead metadata")
        let draft=state.payload(updated as NSDictionary,editing:true)?["draft"] as? NSDictionary
        check(draft?["assignmentDue"] as? Date==state.date && draft?["teacherDue"]==nil && draft?["personalDue"]==nil && draft?["leadDays"]==nil,"one deadline in review payload")
        state.load(record as NSDictionary)
        check(state.notes.isEmpty && state.reminderOffsets==[10080,4320,1440,60,0],"source summary never becomes user notes and new tasks use five reminders")
        var suggested=relative;suggested.removeValue(forKey:"due");suggested["needsDate"]=true;suggested["suggestedDue"]=Date(timeIntervalSince1970:2_100_000_000);suggested["dateBasis"]=["date":Date(),"commit":"abc123"]
        state.load(suggested as NSDictionary)
        check(state.date==suggested["suggestedDue"] as? Date && state.hasDate && state.dateConfirmed && state.payload(suggested as NSDictionary,editing:true) != nil,"relative date with provenance is prefilled and saves without adopt action")
        check(state.payload(suggested as NSDictionary,editing:false)==nil,"relative dates still excluded from unattended batch confirmation")
        suggested["needsTime"]=true;state.load(suggested as NSDictionary);check(!state.hasDate && !state.dateConfirmed,"missing time cannot use a suggestion")
        suggested["needsTime"]=false;suggested["warnings"]=["conflicting dates"];state.load(suggested as NSDictionary);check(!state.dateConfirmed,"conflicting evidence requires completion")
        suggested.removeValue(forKey:"warnings");suggested.removeValue(forKey:"dateBasis");state.load(suggested as NSDictionary);check(!state.hasDate,"unverified suggestion cannot prefill")
        updated["existingTask"]=["title":"原名称","notes":"","due":state.date,"reminderOffsets":[300,0]] as NSDictionary
        state.load(updated as NSDictionary);check(state.notes.isEmpty && state.reminderOffsets==[300,0],"existing empty notes and custom reminders preserved")
        let checkedState=ReviewState();checkedState.refresh([record as NSDictionary]);checkedState.checked=["source-1"]
        var reviewed=record;reviewed["reviewStatus"]="已导入";checkedState.refresh([reviewed as NSDictionary])
        check(checkedState.checked.isEmpty,"reviewed source immediately leaves batch selection even in all-results filter")
        let savedState=ReviewState();savedState.refresh([record as NSDictionary]);savedState.dirty=true
        savedState.save={_ in savedState.refresh([]);return ""}
        check(savedState.saveCurrent(advance:false) && savedState.records.isEmpty && savedState.current==nil,"saved source removed by refresh cannot leave a stale review detail")
        let courseReview=CourseState();var courseRecord=record;courseRecord["existingTask"]=["title":"作业","notes":"保存后的备注","due":Date(),"reminderOffsets":[60,0]]
        courseReview.update([courseRecord as NSDictionary],selected:"source-1",information:"",empty:"",paused:false)
        check(courseReview.review.notes=="保存后的备注" && courseReview.review.current != nil,"course side editor loads persisted task notes")
        var joined:[String:Any]=["id":"task-uuid","confirmed":true,"notes":"保存后的备注","reviewRecord":courseRecord]
        courseReview.update([joined as NSDictionary],selected:"task-uuid",information:"",empty:"",paused:false)
        check(courseReview.review.selected=="source-1" && courseReview.selected=="task-uuid","joined task row maps to the correct review source")
        courseReview.review.notes="未保存草稿";courseReview.review.dirty=true;courseRecord["blobSHA"]="updated-source";joined["reviewRecord"]=courseRecord
        courseReview.update([joined as NSDictionary],selected:"task-uuid",information:"",empty:"",paused:false)
        check(courseReview.review.notes=="未保存草稿" && courseReview.review.current?["blobSHA"] as? String=="v1","course background update preserves draft and source version")
        courseReview.update([],selected:"",information:"",empty:"没有匹配",paused:false)
        check(courseReview.current?["id"] as? String=="task-uuid" && courseReview.review.notes=="未保存草稿","search filtering cannot hide or destroy course draft")
        courseReview.review.save={_ in "写入失败"};check(!courseReview.review.saveCurrent(advance:false) && courseReview.review.dirty,"inline save failure retains notes")
        let removal=CourseState();removal.update([record as NSDictionary],selected:"source-1",information:"",empty:"",paused:false)
        removal.review.dirty=true
        var next=record;next["id"]="source-next"
        removal.review.save={_ in removal.update([next as NSDictionary],selected:"source-next",information:"",empty:"",paused:false);return ""}
        check(removal.review.saveCurrent(advance:false) && removal.selected=="source-next" && removal.review.selected=="source-next","course save reconciles selection after synchronous dirty refresh")
        removal.review.dirty=true;removal.review.save={_ in removal.update([],selected:"",information:"",empty:"暂无待审核作业",paused:false);return ""}
        check(removal.review.saveCurrent(advance:false) && removal.current==nil && removal.review.current==nil && !removal.review.dirty,"final course save clears row and draft together")
        let settings=SettingsState();settings.apply(["mode":"rules","endpoint":"http://localhost:11434","model":"","automaticImport":true] as NSDictionary)
        settings.key="temporary input";settings.dirty=true;settings.save={_,_ in "失败"};check(!settings.persist() && settings.dirty && !settings.key.isEmpty,"failed settings save preserves draft")
        settings.save={config,key in check(config["key"]==nil && key=="temporary input","credential separated from settings dictionary");return ""}
        check(settings.persist() && !settings.dirty && settings.key.isEmpty,"successful settings save clears secret input")
        check(settings.localAutomatic,"legacy local automatic preference defaults on")
        settings.localProbe={configuration,action,ready in check(configuration["key"]==nil && configuration["mode"] as? String=="local","probe config contains no cloud key");ready(["models":[["name":"installed","digest":"new-digest"] as NSDictionary],"message":"connected"] as NSDictionary)}
        settings.model="installed";settings.probe("models");check(!settings.localBusy && settings.installedModels.count==1 && settings.modelDigest=="new-digest","local detection updates installed models and cache identity")
        let courseState=CourseState();courseState.update([record as NSDictionary],selected:"source-1",information:"",empty:"",paused:false)
        check(courseState.current?["id"] as? String=="source-1","course detail remains linked to stable selection")
        courseState.update([],selected:"source-1",information:"all-course summary",empty:"",paused:true)
        check(courseState.current==nil && courseState.information=="all-course summary","all-course summary never retains stale selected material")
        let setup=SetupState();setup.update([["fork":"student/one"],["fork":"student/two"]],step:0,busy:false,message:"")
        setup.selected=["student/one","student/two"];setup.paths=["student/one":"original"]
        var setupPayload:NSDictionary?;setup.action={setupPayload=$0};setup.send("select")
        check((setupPayload?["selected"] as? [String])?.count==2,"setup emits one multi-course selection")
        setup.update([["fork":"student/one","path":""],["fork":"student/two","path":"chosen"]],step:1,busy:true,message:"checking")
        check(setup.paths["student/one"]=="" && setup.paths["student/two"]=="chosen","ambiguous directory clears stale automatic match")
        check(setup.busy && setup.step==1 && setup.selected.count==2,"background setup retains selection and operation stage")
        setup.query="two";check(setup.visible.count==1,"setup search filters course names")
        setup.send("link");check((setupPayload?["paths"] as? [String:String])?["student/two"]=="chosen","setup links explicit course paths independently of current sidebar selection")
        setup.context=["code":"ABCD-EFGH"] as NSDictionary;setup.update(setup.records,step:0,busy:true,message:"waiting")
        check(setup.step==0 && setup.context["code"] as? String=="ABCD-EFGH","device code persists through background refresh")
        setup.update(setup.records,step:3,busy:false,message:"checked")
        check(setup.selected.count==2 && setup.paths["student/two"]=="chosen","wizard stages preserve selections and paths")
        setup.send("close");check(setupPayload?["action"] as? String=="close","wizard cancellation is explicit")
        let nested=NSMutableDictionary(dictionary:["title":"原文"])
        let mutable=NSMutableDictionary(dictionary:["fork":"student/one","id":"source-1","status":"待关联","course":nested,"matches":NSMutableArray(array:["first"])])
        setup.query="";setup.update([mutable],step:2,busy:false,message:"")
        let firstRows=workspaceRows(setup.records,key:"fork")
        let identity=firstRows[0].id
        var identities=[identity:"retained"]
        mutable["status"]="已关联";mutable["path"]="second";nested["title"]="变更原文"
        (mutable["matches"] as! NSMutableArray).add("second")
        check(setup.records[0]["status"] as? String=="待关联","controller mutation cannot alter rendered setup snapshot")
        check((setup.records[0]["course"] as? NSDictionary)?["title"] as? String=="原文","nested dictionaries are detached from controller mutation")
        check((setup.records[0]["matches"] as? [String])==["first"],"nested arrays are detached from controller mutation")
        setup.update([mutable],step:3,busy:true,message:"检查中")
        let secondRows=workspaceRows(setup.records,key:"fork")
        check(secondRows[0].id==identity && firstRows[0].record["status"] as? String=="待关联","row identity remains stable across state and stage changes")
        identities[secondRows[0].id]="updated"
        check(identities.count==1 && identities[identity]=="updated","updated row uses a stable dictionary key")
        let another:NSDictionary=["fork":"student/two","id":"source-2"]
        check(workspaceRows([another,mutable],key:"fork")[1].id==identity,"reordering keeps identity tied to repository rather than index")
        let malformed=workspaceRows([mutable,mutable,[:],[:]],key:"fork")
        check(Set(malformed.map(\.id)).count==4,"duplicate or missing source IDs cannot collide in SwiftUI")
        state.refresh([mutable]);mutable["title"]="外部变更"
        check(state.records[0]["title"]==nil,"review snapshots are detached too")
        courseState.update([mutable],selected:"source-1",information:"",empty:"",paused:false)
        mutable["title"]="再次变更"
        check(courseState.current?["title"] as? String=="外部变更","course selection uses source identity with an immutable snapshot")
        print("PASS: \(count) SwiftUI state assertions")
    }
}
