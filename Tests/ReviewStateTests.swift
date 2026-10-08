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
        state.refresh([updated as NSDictionary]);check(state.customPersonalDate && state.personalDate==Date(timeIntervalSince1970:1_900_000_000),"custom personal deadline survives review refresh")
        state.hasDate=true;state.dateConfirmed=true;state.customPersonalDate=false
        check(((state.payload(updated as NSDictionary,editing:true)?["draft"] as? NSDictionary)?["leadDays"] as? Int)==0,"leaving manual date mode clamps legacy negative lead")
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
