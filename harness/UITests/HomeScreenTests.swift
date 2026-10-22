import XCTest

/// Like a friend would: Safari → Share → Add to Home Screen → tap the icon → full-screen app → Start demo → tabs.
/// Env (from run.sh): OUT = folder for screenshots.
@MainActor
final class HomeScreenTests: XCTestCase {
    let env = ProcessInfo.processInfo.environment
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    var step = 0

    /// Screenshot + UI tree (the tree says what to tap when a label changes between iOS versions).
    func shot(_ name: String, _ app: XCUIApplication) {
        guard let out = env["OUT"] else { return }
        step += 1
        let base = URL(fileURLWithPath: out).appendingPathComponent(String(format: "%02d-%@", step, name))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: base.appendingPathExtension("png"))
        try? app.debugDescription.write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
    }

    /// Taps the first hittable element labelled one of `labels`, buttons first.
    @discardableResult
    func tap(_ app: XCUIApplication, _ labels: [String], timeout: Double = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for query in [app.buttons, app.cells, app.descendants(matching: .any)] {
                for label in labels {
                    let el = query.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
                    if el.exists && el.isHittable { el.tap(); return true }
                }
            }
            usleep(300_000)
        } while Date() < deadline
        return false
    }

    func testHomeScreenWebApp() throws {
        safari.activate()
        sleep(6)
        // First-run Safari tip ("View Bookmarks, Share Menu…"): it can show up late and swallows the next tap.
        tap(safari, ["Close"], timeout: 8)
        shot("safari", safari)

        // iOS 26 puts Share in the "…" menu; older iOS has it in the toolbar.
        if !tap(safari, ["Share"], timeout: 2) {
            tap(safari, ["Close"], timeout: 1)
            tap(safari, ["More", "Page Menu", "Tab Menu"])
            shot("menu", safari)
            XCTAssertTrue(tap(safari, ["Share"]), "Share not found")
        }
        sleep(2)
        shot("share-sheet", safari)
        var found = tap(safari, ["Add to Home Screen"], timeout: 3)
        for _ in 0..<2 where !found { safari.swipeUp(); found = tap(safari, ["Add to Home Screen"], timeout: 2) }
        XCTAssertTrue(found, "Add to Home Screen not found")
        // The sheet loads the page's name and icon first; "Add" stays greyed out until then.
        let add = safari.buttons["Add"]
        for _ in 0..<40 where !(add.exists && add.isEnabled) { usleep(500_000) }
        shot("add-sheet", safari)
        XCTAssertTrue(add.isEnabled, "Add button stayed disabled")
        add.tap()
        sleep(3)

        XCUIDevice.shared.press(.home)
        sleep(2)
        let icon = springboard.icons.matching(NSPredicate(format: "label CONTAINS[c] 'setcrew'")).firstMatch
        for _ in 0..<3 where icon.exists && !icon.isHittable { springboard.swipeLeft(); sleep(1) }
        shot("home-screen", springboard)
        XCTAssertTrue(icon.exists, "SetCrew icon not on the Home Screen")
        icon.tap()
        sleep(8)

        // ponytail: guessed bundle id of Home Screen web apps; the UI tree in OUT shows the real one if this misses.
        let webapp = XCUIApplication(bundleIdentifier: "com.apple.webapp")
        let app = webapp.state == .runningForeground ? webapp : springboard
        shot("webapp-open", app)

        // Demo build: one button, no account, example history pre-filled.
        tap(app, ["Start demo"])
        sleep(4)
        shot("demo-started", app)

        // Tab bar: Home · Train · + · Feed · Progress. Coordinate taps when labels aren't reachable.
        let slots = ["Train": 1, "Feed": 3, "Progress": 4, "Home": 0]
        for tab in ["Train", "Feed", "Progress", "Home"] {
            if !tap(app, [tab], timeout: 2) {
                app.coordinate(withNormalizedOffset: CGVector(dx: (Double(slots[tab]!) + 0.5) / 5, dy: 0.95)).tap()
            }
            sleep(3)
            shot(tab.lowercased(), app)
        }
    }
}
