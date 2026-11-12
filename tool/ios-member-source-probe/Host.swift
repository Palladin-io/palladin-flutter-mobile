import UIKit
@main final class SyntheticHost: UIResponder, UIApplicationDelegate {
    var window:UIWindow?
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?) -> Bool {
        do {
            let group="group.invalid.example.productionruntime"
            guard let directory=FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group),
                  let seedURL=Bundle.main.url(forResource:"source",withExtension:"json"),
                  let dbURL=Bundle.main.url(forResource:"vault_member_sync",withExtension:"db") else { throw SharedMemberSourceError.unavailable }
            let seed=try JSONSerialization.jsonObject(with:Data(contentsOf:seedURL)) as! [String:Any]
            let fence=try SharedMemberSourceFence(containerURL:directory,accessGroup:group)
            let session=try fence.beginSession(sessionID:UUID().uuidString,profileBinding:seed["profileBinding"] as! String,claims:SharedMemberSourceClaims(arguments:seed["claims"] as! [String:Any]),accountUnlock:seed["accountUnlock"] as! [String:Any])
            let denied=try fence.invalidate(session)
            let source=directory.appendingPathComponent("member-source")
            try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
            let destination=source.appendingPathComponent("vault_member_sync.db")
            if FileManager.default.fileExists(atPath:destination.path) { try FileManager.default.removeItem(at:destination) }
            try FileManager.default.copyItem(at:dbURL,to:destination)
            try fence.activate(denied)
            NSLog("SYNTHETIC_MEMBER_SOURCE_READY")
        } catch { NSLog("SYNTHETIC_MEMBER_SOURCE_FAILED") }
        let vc=UIViewController();vc.view.backgroundColor = .systemBackground
        let title=UILabel(frame:CGRect(x:20,y:90,width:350,height:50)); title.text="Synthetic production-runtime test";vc.view.addSubview(title)
        let username=UITextField(frame:CGRect(x:20,y:160,width:350,height:50));username.placeholder="Synthetic username";username.textContentType = .username;username.borderStyle = .roundedRect;vc.view.addSubview(username)
        let password=UITextField(frame:CGRect(x:20,y:230,width:350,height:50));password.placeholder="Synthetic password";password.textContentType = .password;password.isSecureTextEntry=true;password.borderStyle = .roundedRect;vc.view.addSubview(password)
        let check=UIButton(type:.system);check.frame=CGRect(x:20,y:300,width:350,height:50);check.setTitle("Check synthetic fill",for:.normal);check.addAction(UIAction{ _ in
            let success=username.text=="synthetic" && password.text=="synthetic-only"
            NSLog(success ? "SYNTHETIC_MEMBER_HANDOFF_PASS" : "SYNTHETIC_MEMBER_HANDOFF_FAIL")
        },for:.touchUpInside);vc.view.addSubview(check)
        window=UIWindow(frame:UIScreen.main.bounds);window?.rootViewController=vc;window?.makeKeyAndVisible();return true
    }
}
