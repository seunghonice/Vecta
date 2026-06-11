import AppKit

enum MainMenuBuilder {
  static func build() -> NSMenu {
    let mainMenu = NSMenu()
    mainMenu.addItem(wrap(appMenu()))
    mainMenu.addItem(wrap(fileMenu()))
    mainMenu.addItem(wrap(editMenu()))
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

  private static func editMenu() -> NSMenu {
    let menu = NSMenu(title: "편집")
    // undo:/redo:는 Swift에서 #selector로 접근 불가(UndoManager가 @objc 미노출)
    // → 문자열 셀렉터 사용. 응답 체인이 NSDocument의 undoManager로 라우팅한다.
    menu.addItem(
      withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = menu.addItem(
      withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "Z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "모두 선택",
      action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
    return menu
  }
}
