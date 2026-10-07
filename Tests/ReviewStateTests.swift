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
        print("PASS: \(count) SwiftUI state assertions")
    }
}
