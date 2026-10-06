import SwiftUI
import SwiftData
import UserNotifications
import UIKit

@main
struct OATScheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup { BootstrapView() }
            .modelContainer(for: CachedDocument.self)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let changeID = info["changeID"] as? String {
            UserDefaults.standard.set(changeID, forKey: "pendingChangeID")
        }
        NotificationCenter.default.post(name: .openChange, object: nil, userInfo: info)
    }
}

struct BootstrapView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var container: AppContainer?
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        Group {
            if let container { RootView().environment(container) }
            else { ProgressView().tint(.indigo) }
        }
        .task {
            guard container == nil else { return }
            let created = AppContainer(context: modelContext)
            container = created
        }
        .preferredColorScheme((AppearanceMode.Value(rawValue: appearance) ?? .system).colorScheme)
    }
}

enum AppearanceMode {
    static var current: AppearanceMode.Value {
        get { Value(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "system") ?? .system }
    }
    enum Value: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { switch self { case .system: "Системное"; case .light: "Светлое"; case .dark: "Тёмное" } }
        var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    }
}

struct RootView: View {
    @Environment(AppContainer.self) private var app
    @State private var selection: UserSelection?
    @State private var deepLinkedChangeID: String?
    @State private var selectedTab = 0
    var body: some View {
        Group {
            if let selection {
                MainTabView(selection: selection, deepLinkedChangeID: $deepLinkedChangeID, selectedTab: $selectedTab)
            } else {
                OnboardingView { newSelection in
                    selection = newSelection
                    app.store.write(newSelection, key: "selection")
                    Task { await app.refresh(selection: newSelection) }
                }
            }
        }
        .task {
            if let restored = app.store.read(UserSelection.self, key: "selection") {
                selection = restored
                Task { await app.refresh(selection: restored) }
            }
            if let pending = UserDefaults.standard.string(forKey: "pendingChangeID") {
                deepLinkedChangeID = pending
                selectedTab = 1
                UserDefaults.standard.removeObject(forKey: "pendingChangeID")
            }
        }
        .onOpenURL { url in
            guard url.scheme == "omaviat", url.host == "changes" else { return }
            deepLinkedChangeID = url.lastPathComponent
            selectedTab = 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChange)) { note in
            deepLinkedChangeID = note.userInfo?["changeID"] as? String
            selectedTab = 1
            UserDefaults.standard.removeObject(forKey: "pendingChangeID")
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetSelection)) { _ in selection = nil }
    }
}

extension Notification.Name { static let openChange = Notification.Name("OATOpenChange") }
extension Notification.Name { static let resetSelection = Notification.Name("OATResetSelection") }

struct MainTabView: View {
    let selection: UserSelection
    @Binding var deepLinkedChangeID: String?
    @Binding var selectedTab: Int
    var body: some View {
        TabView(selection: $selectedTab) {
            ScheduleView(selection: selection)
                .tabItem { Label("Расписание", systemImage: "calendar") }
                .tag(0)
            ChangesView(selection: selection, deepLinkedChangeID: $deepLinkedChangeID)
                .tabItem { Label("Изменения", systemImage: "arrow.triangle.2.circlepath") }
                .tag(1)
            SettingsView(selection: selection)
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(2)
        }
    }
}

