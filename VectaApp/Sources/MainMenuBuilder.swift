import AppKit

enum MainMenuBuilder {
  static func build() -> NSMenu {
    let mainMenu = NSMenu()
    mainMenu.addItem(wrap(appMenu()))
    mainMenu.addItem(wrap(fileMenu()))
    mainMenu.addItem(wrap(editMenu()))
    mainMenu.addItem(wrap(objectMenu()))
    return mainMenu
  }

  private static func wrap(_ menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem()
    item.submenu = menu
    return item
  }

  private static func appMenu() -> NSMenu {
    let menu = NSMenu(title: "Vecta")
    menu.addItem(
      withTitle: "Vecta에 관하여",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Vecta 종료",
      action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    return menu
  }

  private static func fileMenu() -> NSMenu {
    let menu = NSMenu(title: "파일")
    menu.addItem(
      withTitle: "새 문서",
      action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
    menu.addItem(
      withTitle: "열기…",
      action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "닫기",
      action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    menu.addItem(
      withTitle: "저장",
      action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
    let saveAs = menu.addItem(
      withTitle: "다른 이름으로 저장…",
      action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
    saveAs.keyEquivalentModifierMask = [.command, .shift]
    return menu
  }

  private static func objectMenu() -> NSMenu {
    let menu = NSMenu(title: "오브젝트")
    menu.addItem(
      withTitle: "그룹",
      action: #selector(VectaDocument.groupSelection(_:)), keyEquivalent: "g")
    let ungroup = menu.addItem(
      withTitle: "그룹 해제",
      action: #selector(VectaDocument.ungroupSelection(_:)), keyEquivalent: "G")
    ungroup.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "앞으로 가져오기",
      action: #selector(VectaDocument.bringForward(_:)), keyEquivalent: "]")
    menu.addItem(
      withTitle: "뒤로 보내기",
      action: #selector(VectaDocument.sendBackward(_:)), keyEquivalent: "[")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "합치기",
      action: #selector(VectaDocument.pathfinderUnite(_:)), keyEquivalent: "")
    menu.addItem(
      withTitle: "빼기",
      action: #selector(VectaDocument.pathfinderSubtract(_:)), keyEquivalent: "")
    menu.addItem(
      withTitle: "교차",
      action: #selector(VectaDocument.pathfinderIntersect(_:)), keyEquivalent: "")
    menu.addItem(
      withTitle: "제외",
      action: #selector(VectaDocument.pathfinderExclude(_:)), keyEquivalent: "")
    return menu
  }

  private static func editMenu() -> NSMenu {
    let menu = NSMenu(title: "편집")
    // undo:/redo:는 Swift에서 #selector로 접근 불가(UndoManager가 @objc 미노출)
    // → 문자열 셀렉터 사용. 응답 체인이 NSDocument의 undoManager로 라우팅한다.
    menu.addItem(
      withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = menu.addItem(
      withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "Z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    // macOS 관례 순서: 실행취소/복귀 → 잘라/복사/붙여/복제 → 모두 선택.
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "잘라내기",
      action: #selector(VectaDocument.cut(_:)), keyEquivalent: "x")
    menu.addItem(
      withTitle: "복사",
      action: #selector(VectaDocument.copy(_:)), keyEquivalent: "c")
    menu.addItem(
      withTitle: "붙여넣기",
      action: #selector(VectaDocument.paste(_:)), keyEquivalent: "v")
    menu.addItem(
      withTitle: "복제",
      action: #selector(VectaDocument.duplicateSelection(_:)), keyEquivalent: "d")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "모두 선택",
      action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
    return menu
  }
}
