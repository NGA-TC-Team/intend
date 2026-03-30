import AppKit

// NSApplicationMain(argc, argv) 는 C 함수로, NSMainNibFile 기반으로 delegate를
// 연결한다. xib가 없는 경우 NSAppDelegateClass (Info.plist) 키를 처리하지 않으므로
// applicationDidFinishLaunching이 호출되지 않는다.
//
// 해결: NSApp.run() 호출 전에 AppDelegate를 직접 생성·연결한다.
// 파일 스코프(전역) 변수: NSApp.delegate는 weak 참조이므로 이 강한 참조가 필수.
private let _appDelegate = AppDelegate()

NSApplication.shared.delegate = _appDelegate
NSApp.run()
