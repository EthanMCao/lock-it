import SwiftUI
import Combine

@main
struct LockITApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = FolderListViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Lock All and Quit") {
                    appDelegate.lockAllAndTerminate(viewModel: viewModel)
                }.keyboardShortcut("q")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()
    private let lifecycle = LifecycleObserver()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        lifecycle.setupObservers(lockAction: { [weak self] in
            self?.lockAll()
        })
    }

    func applicationWillTerminate(_ notification: Notification) {
        lockAll()
    }

    @MainActor
    func lockAllAndTerminate(viewModel: FolderListViewModel) {
        Task {
            await viewModel.lockAll()
            NSApp.terminate(nil)
        }
    }

    private func lockAll() {
        Task {
            await FolderListViewModel.shared.lockAll()
        }
    }
}

final class LifecycleObserver {
    private var observers: [NSObjectProtocol] = []

    func setupObservers(lockAction: @escaping () -> Void) {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in lockAction() })
        observers.append(ws.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in lockAction() })
        observers.append(ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in lockAction() })
    }

    deinit {
        let ws = NSWorkspace.shared.notificationCenter
        for o in observers { ws.removeObserver(o) }
    }
}

