import SwiftUI
import SwiftGodot
import SwiftGodotKit
import UIKit
import HealthKit

struct ContentView: View {
    @State var app = GodotApp(packFile: "Parsec.pck")

    var body: some View {
        GodotViewControllerWrapper(app: app)
            .ignoresSafeArea(.all)
    }
}

private struct GodotViewControllerWrapper: UIViewControllerRepresentable {
    let app: GodotApp

    func makeUIViewController(context: Context) -> GodotViewController {
        GodotViewController(app: app)
    }

    func updateUIViewController(_ vc: GodotViewController, context: Context) {}
}

private final class GodotViewController: UIViewController {
    let godotApp: GodotApp
    private let healthKit = HealthKitManager()
    private weak var storedGodotView: UIGodotAppView?
    private var syncPollTimer: Foundation.Timer?

    init(app: GodotApp) {
        self.godotApp = app
        super.init(nibName: nil, bundle: nil)
        app.registerEventHandler { event in
            print("[GodotEvent] \(event)")
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        syncPollTimer?.invalidate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        print("[Debug] frame=\(view.frame)")
    }

    override func loadView() {
        let godotView = UIGodotAppView()
        godotView.contentScaleFactor = UIScreen.main.scale
        godotView.isMultipleTouchEnabled = true
        godotView.isUserInteractionEnabled = false

        godotApp.configureLaunch(source: nil, scene: nil)
        godotApp.start()
        godotView.app = godotApp

        storedGodotView = godotView

        let wrapper = GodotInputView(godotView: godotView)
        wrapper.isMultipleTouchEnabled = true
        view = wrapper

        // Poll every 0.25s — bypasses the broken @Callable path for step sync, and keeps the
        // device orientation change (SaveManager.target_orientation) snappy so the loading cover
        // shown during the rotation (SceneManager) can be brief.
        syncPollTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkSyncRequest()
            self?.checkOrientation()
        }
    }

    // Reads SaveManager.target_orientation ("portrait"/"landscape") and, when it changes, flips
    // the app-wide orientation mask and asks iOS to rotate the window to match. Menus stay
    // portrait; the game requests landscape, so the player turns the phone sideways to play.
    private var currentWantsLandscape = false
    private func checkOrientation() {
        guard let instance = godotApp.instance, instance.isStarted() else { return }
        guard let sceneTree = Engine.getMainLoop() as? SceneTree,
              let root = sceneTree.root else { return }
        guard let saveManager = root.findChild(pattern: "SaveManager", recursive: false, owned: false) else { return }
        let v = saveManager.get(property: StringName("target_orientation"))
        guard let s = String(v) else { return }
        let wantLandscape = (s == "landscape")
        guard wantLandscape != currentWantsLandscape else { return }
        currentWantsLandscape = wantLandscape

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            AppOrientation.mask = wantLandscape ? .landscape : .portrait
            self.setNeedsUpdateOfSupportedInterfaceOrientations()
            if #available(iOS 16.0, *),
               let scene = self.view.window?.windowScene {
                let orientations: UIInterfaceOrientationMask = wantLandscape ? .landscapeRight : .portrait
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
            } else {
                UIDevice.current.setValue(
                    (wantLandscape ? UIInterfaceOrientation.landscapeRight : .portrait).rawValue,
                    forKey: "orientation")
            }
        }
    }

    private func checkSyncRequest() {
        guard let instance = godotApp.instance, instance.isStarted() else { return }
        guard let sceneTree = Engine.getMainLoop() as? SceneTree,
              let root = sceneTree.root else { return }
        guard let saveManager = root.findChild(pattern: "SaveManager", recursive: false, owned: false) else { return }
        let requestVar = saveManager.get(property: StringName("swift_request"))
        guard let requestStr = String(requestVar),
              requestStr == "sync_steps" || requestStr == "preview_steps" else { return }

        let isPreview = (requestStr == "preview_steps")
        print("[ContentView] swift_request=\(requestStr)")
        saveManager.set(property: StringName("swift_request"), value: Variant(""))

        guard let godotView = storedGodotView else { return }
        handleStepsRequest(godotView: godotView, isPreview: isPreview)
    }

    private func handleStepsRequest(godotView: UIGodotAppView, isPreview: Bool) {
        healthKit.requestWeekSteps { [weak godotView] result in
            let reply = VariantDictionary()
            switch result {
            case .success(let stepsByDay):
                print("[ContentView] steps fetched (preview=\(isPreview)): \(stepsByDay)")
                // Preview sends all days (including 0) so boxes show accurate unsynced counts.
                // Sync filters 0-step days to avoid overwriting good data with a transient 0.
                reply["action"] = Variant(isPreview ? "steps_preview" : "steps_ready")
                for (dateStr, count) in stepsByDay {
                    if isPreview || count > 0 {
                        reply[dateStr] = Variant(Int64(count))
                    }
                }
            case .failure(let err):
                print("[ContentView] steps unavailable: \(err)")
                reply["action"] = Variant("steps_unavailable")
            }
            DispatchQueue.main.async {
                godotView?.app?.emitMessage(reply)
            }
        }
    }
}

// MARK: - Touch injection (bypasses broken DisplayServerAppleEmbedded.touch_press hash)

private final class GodotInputView: UIView {
    private let godotView: UIGodotAppView
    // Stable finger → index mapping. UITouch identity is stable within a gesture.
    private var touchMap: [ObjectIdentifier: Int32] = [:]
    private var nextIdx: Int32 = 0

    init(godotView: UIGodotAppView) {
        self.godotView = godotView
        super.init(frame: .zero)
        godotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(godotView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let instance = godotView.app?.instance, instance.isStarted() else { return }
        let scale = godotView.contentScaleFactor
        for touch in touches {
            let id  = ObjectIdentifier(touch)
            let idx = nextIdx; nextIdx += 1
            touchMap[id] = idx
            let pos = touch.location(in: godotView)
            let evt = InputEventScreenTouch()
            evt.index    = idx
            evt.position = Vector2(x: Float(pos.x * scale), y: Float(pos.y * scale))
            evt.pressed  = true
            Input.parseInputEvent(evt)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let instance = godotView.app?.instance, instance.isStarted() else { return }
        let scale = godotView.contentScaleFactor
        for touch in touches {
            guard let idx = touchMap[ObjectIdentifier(touch)] else { continue }
            let pos  = touch.location(in: godotView)
            let prev = touch.previousLocation(in: godotView)
            let evt = InputEventScreenDrag()
            evt.index    = idx
            evt.position = Vector2(x: Float(pos.x  * scale), y: Float(pos.y  * scale))
            evt.relative = Vector2(x: Float((pos.x - prev.x) * scale), y: Float((pos.y - prev.y) * scale))
            Input.parseInputEvent(evt)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        injectEnd(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        injectEnd(touches)
    }

    private func injectEnd(_ touches: Set<UITouch>) {
        guard let instance = godotView.app?.instance, instance.isStarted() else { return }
        let scale = godotView.contentScaleFactor
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let idx = touchMap.removeValue(forKey: id) else { continue }
            if touchMap.isEmpty { nextIdx = 0 }
            let pos = touch.location(in: godotView)
            let evt = InputEventScreenTouch()
            evt.index    = idx
            evt.position = Vector2(x: Float(pos.x * scale), y: Float(pos.y * scale))
            evt.pressed  = false
            Input.parseInputEvent(evt)
        }
    }
}

// MARK: - HealthKit

private final class HealthKitManager {
    private let store: HKHealthStore?

    init() {
        store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }

    enum StepError: Error { case unavailable, denied }

    // Fetches total steps for each of the past 6 days (including today) — matches
    // the 6 day-boxes shown in sync_steps.gd. Returns { "YYYY-MM-DD": stepCount }.
    func requestWeekSteps(completion: @escaping (Result<[String: Int], StepError>) -> Void) {
        guard let store else {
            completion(.failure(.unavailable))
            return
        }
        let stepType = HKQuantityType(.stepCount)
        store.requestAuthorization(toShare: [], read: [stepType]) { success, _ in
            guard success else {
                completion(.failure(.denied))
                return
            }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"

            var results: [String: Int] = [:]
            let lock = NSLock()
            let group = DispatchGroup()

            for offset in 0...5 {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                      let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
                let dateStr = formatter.string(from: day)
                let predicate = HKQuery.predicateForSamples(withStart: day, end: nextDay)
                group.enter()
                let query = HKStatisticsQuery(
                    quantityType: stepType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, result, _ in
                    let count = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                    lock.lock()
                    results[dateStr] = count
                    lock.unlock()
                    group.leave()
                }
                store.execute(query)
            }

            group.notify(queue: .global()) {
                completion(.success(results))
            }
        }
    }
}
