import SwiftUI
import SwiftData
import UserNotifications
import UIKit

@main
struct OATScheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            BootstrapView()
        }
        .modelContainer(for: CachedDocument.self)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
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
            if let container {
                RootView()
                    .environment(container)
                    .transition(.opacity)
            } else {
                ProgressView()
                    .tint(.indigo)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: container != nil)
        .task {
            guard container == nil else { return }
            container = AppContainer(context: modelContext)
        }
        .preferredColorScheme((AppearanceMode.Value(rawValue: appearance) ?? .system).colorScheme)
    }
}

enum AppearanceMode {
    static var current: AppearanceMode.Value {
        Value(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "system") ?? .system
    }

    enum Value: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "Системное"
            case .light: "Светлое"
            case .dark: "Тёмное"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
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
                MainTabView(
                    selection: selection,
                    deepLinkedChangeID: $deepLinkedChangeID,
                    selectedTab: $selectedTab
                )
                .transition(.opacity.combined(with: .scale(scale: 0.99)))
            } else {
                OnboardingView { newSelection in
                    withAnimation(.snappy) {
                        selection = newSelection
                    }
                    app.store.write(newSelection, key: "selection")
                    if UserDefaults.standard.bool(forKey: "testMode"),
                       let data = try? JSONEncoder().encode(newSelection) {
                        UserDefaults.standard.set(data, forKey: "demoSelection")
                    }
                    Task { await app.refresh(selection: newSelection) }
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: selection)
        .task {
            if let restored = app.store.read(UserSelection.self, key: "selection") {
                selection = restored
                if UserDefaults.standard.bool(forKey: "testMode"),
                   let data = try? JSONEncoder().encode(restored) {
                    UserDefaults.standard.set(data, forKey: "demoSelection")
                }
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
            withAnimation(.snappy) { selectedTab = 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChange)) { note in
            deepLinkedChangeID = note.userInfo?["changeID"] as? String
            withAnimation(.snappy) { selectedTab = 1 }
            UserDefaults.standard.removeObject(forKey: "pendingChangeID")
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetSelection)) { _ in
            UserDefaults.standard.set(false, forKey: "testMode")
            UserDefaults.standard.removeObject(forKey: "demoSelection")
            withAnimation(.snappy) { selection = nil }
        }
    }
}

extension Notification.Name {
    static let openChange = Notification.Name("OATOpenChange")
    static let resetSelection = Notification.Name("OATResetSelection")
}

struct MainTabView: View {
    let selection: UserSelection
    @Binding var deepLinkedChangeID: String?
    @Binding var selectedTab: Int
    @AppStorage("testMode") private var testMode = false

    var body: some View {
        VStack(spacing: 0) {
            if testMode {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                    Text("Тестовый режим — данные демонстрационные")
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel("Тестовый режим. Данные демонстрационные.")
            }

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
        .animation(.snappy, value: testMode)
    }
}
