import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(AppContainer.self) private var app
    let onComplete: (UserSelection) -> Void

    @State private var step = 0
    @State private var categories: [CollegeCategory] = []
    @State private var groups: [StudentGroup] = []
    @State private var chosenCategory: CollegeCategory?
    @State private var chosenGroup: StudentGroup?
    @State private var query = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var diagnosticCopied = false
    @AppStorage("testMode") private var testMode = false

    var body: some View {
        NavigationStack {
            ZStack {
                OATAppBackground()

                Group {
                    if step == 0 {
                        welcome
                    } else if step == 1 {
                        chooseGroup
                    } else {
                        notifications
                    }
                }
            }
            .navigationTitle(step == 1 ? "Ваша группа" : "")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [OATTheme.blue.opacity(0.28), OATTheme.cyan.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 236, height: 236)

                Image(systemName: "calendar")
                    .font(.system(size: 105, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))

                Image(systemName: "airplane")
                    .font(.system(size: 66, weight: .semibold))
                    .rotationEffect(.degrees(-10))
                    .foregroundStyle(OATTheme.blue)
                    .offset(x: 20, y: 16)
            }
            .padding(24)
            .oatGlassSurface(radius: 54, tint: OATTheme.blue.opacity(0.06))

            VStack(spacing: 8) {
                Text("ОмАВИАТ Расписание")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Пары, изменения и уведомления — в одном приложении.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                step = 1
                Task { await loadCategories() }
            } label: {
                HStack {
                    Text("Начать")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .oatGlassButton(prominent: true)
            .controlSize(.large)
        }
        .padding(24)
    }

    private var chooseGroup: some View {
        VStack(spacing: 12) {
            if testMode {
                testModeBanner
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Найти группу", text: $query)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .oatGlassSurface(radius: 16, interactive: true)
            .padding(.horizontal)

            if !testMode, let error, !categories.isEmpty, chosenCategory != nil, groups.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Не удалось загрузить группы", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Скопировать диагностику") { copyDiagnostics() }
                            .oatGlassButton()
                        Button("Тестовый режим") { activateTestMode() }
                            .oatGlassButton()
                    }
                    .font(.caption)
                }
                .padding(14)
                .oatGlassSurface(radius: 18, tint: .orange.opacity(0.08))
                .padding(.horizontal)
            }

            if categories.isEmpty && isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Загружаю список корпусов…")
                        .foregroundStyle(.secondary)
                }
                .padding(28)
                .oatGlassSurface(radius: 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if let error, categories.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 42))
                        .foregroundStyle(.orange)

                    Text("Не удалось получить список")
                        .font(.title3.bold())

                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Повторить") {
                        Task { await loadCategories(forceLive: true) }
                    }
                    .oatGlassButton(prominent: true)

                    Button("Скопировать диагностику") {
                        copyDiagnostics()
                    }
                    .oatGlassButton()

                    Button("Открыть тестовый режим") {
                        activateTestMode()
                    }
                    .oatGlassButton()
                }
                .padding(20)
                .oatGlassSurface(radius: 26)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(categories) { category in
                        Section {
                            if chosenCategory?.id == category.id {
                                ForEach(filteredGroups) { group in
                                    Button {
                                        withAnimation(.snappy) {
                                            chosenGroup = group
                                        }
                                    } label: {
                                        HStack {
                                            Text(group.name)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            if chosenGroup?.id == group.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(OATTheme.blue)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            Button {
                                Task { await select(category) }
                            } label: {
                                HStack {
                                    Label(category.title, systemImage: "building.2")
                                    Spacer()
                                    Image(systemName: chosenCategory?.id == category.id ? "chevron.down" : "chevron.right")
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .oatClearScrollBackground()
            }

            if let chosenGroup {
                Button {
                    step = 2
                } label: {
                    HStack {
                        Text("Продолжить")
                        Spacer()
                        Text(chosenGroup.name)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .oatGlassButton(prominent: true)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .task {
            if categories.isEmpty { await loadCategories() }
        }
    }

    private var testModeBanner: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Тестовый режим")
                        .font(.subheadline.bold())
                    Text("Не удалось получить реальные данные OAT. Используются демонстрационные группы и расписание.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    copyDiagnostics()
                } label: {
                    Label(
                        diagnosticCopied ? "Скопировано" : "Скопировать",
                        systemImage: diagnosticCopied ? "checkmark" : "doc.on.doc"
                    )
                }
                .oatGlassButton()

                Button {
                    Task { await loadCategories(forceLive: true) }
                } label: {
                    Label("Проверить сайт", systemImage: "arrow.clockwise")
                }
                .oatGlassButton()
                .disabled(isLoading)
            }
            .font(.caption)
        }
        .padding(14)
        .oatGlassSurface(radius: 18, tint: .orange.opacity(0.08))
        .padding(.horizontal)
    }

    private var filteredGroups: [StudentGroup] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return groups }
        return groups.filter { normalize($0.name).contains(normalizedQuery) }
    }

    private var notifications: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 58))
                .foregroundStyle(.orange)
                .padding(24)
                .oatGlassSurface(radius: 34, tint: .orange.opacity(0.08))

            Text("Узнавайте об изменениях сразу")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("Мы сообщим, если для (chosenGroup?.name ?? "вашей группы") появятся замены или отмены занятий.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if testMode {
                OATGlassStatusBanner(
                    title: "В тестовом режиме используются демонстрационные изменения",
                    systemImage: "wrench.and.screwdriver.fill",
                    tint: .orange
                )
            }

            Spacer()

            Button("Включить уведомления") {
                Task {
                    _ = await app.notifications.requestAuthorization()
                    finish()
                }
            }
            .oatGlassButton(prominent: true)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            Button("Позже", action: finish)
                .oatGlassButton()
                .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private func finish() {
        guard let category = chosenCategory, let group = chosenGroup else { return }
        onComplete(UserSelection(category: category, group: group))
    }

    private func loadCategories(forceLive: Bool = false) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        if forceLive {
            testMode = false
            UserDefaults.standard.removeObject(forKey: "demoSelection")
            categories = []
            groups = []
            chosenCategory = nil
            chosenGroup = nil
            await NetworkDiagnosticsStore.shared.recordAppEvent(
                "LIVE RETRY",
                details: "User requested another live oat.ru attempt from test mode."
            )
        }

        do {
            let loaded = try await app.scheduleService.loadCategories()
            guard !loaded.isEmpty else {
                await NetworkDiagnosticsStore.shared.recordAppEvent(
                    "TEST MODE FALLBACK",
                    details: "loadCategories returned an empty array."
                )
                activateTestMode()
                return
            }
            categories = loaded
            testMode = false
        } catch {
            self.error = error.localizedDescription
            await NetworkDiagnosticsStore.shared.recordAppEvent(
                "TEST MODE FALLBACK",
                details: "loadCategories failed: (String(reflecting: type(of: error))) · (error.localizedDescription)"
            )
            activateTestMode()
        }
    }

    private func activateTestMode() {
        testMode = true
        error = nil
        categories = [DemoData.category]
        chosenCategory = nil
        chosenGroup = nil
        groups = []
    }

    private func select(_ category: CollegeCategory) async {
        chosenCategory = category
        chosenGroup = nil
        groups = []
        error = nil
        isLoading = true
        defer { isLoading = false }

        if category.id == DemoData.category.id {
            groups = DemoData.groups
            return
        }

        do {
            groups = try await app.scheduleService.loadGroups(in: category)
            if groups.isEmpty { throw AppFailure.noData }
        } catch {
            self.error = error.localizedDescription
            await NetworkDiagnosticsStore.shared.recordAppEvent(
                "GROUP LOAD FAILED",
                details: "category=(category.slug) · (String(reflecting: type(of: error))) · (error.localizedDescription)"
            )
        }
    }

    private func copyDiagnostics() {
        Task {
            let report = await NetworkDiagnosticsStore.shared.report()
            await MainActor.run {
                UIPasteboard.general.string = report
                diagnosticCopied = true
            }
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { diagnosticCopied = false }
        }
    }

    private func normalize(_ value: String) -> String {
        value.filter { $0.isLetter || $0.isNumber }.uppercased()
    }
}
