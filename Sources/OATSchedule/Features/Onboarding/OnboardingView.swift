import SwiftUI

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
    @AppStorage("testMode") private var testMode = false

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 { welcome }
                else if step == 1 { chooseGroup }
                else { notifications }
            }
            .navigationTitle(step == 1 ? "Ваша группа" : "")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.18), .cyan.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 230, height: 230)
                Image(systemName: "cloud.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.blue.opacity(0.12))
                    .offset(x: -72, y: -44)
                Image(systemName: "airplane")
                    .font(.system(size: 92, weight: .medium))
                    .rotationEffect(.degrees(-12))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.blue, .cyan)
            }
            Text("ОмАВИАТ\nРасписание")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Расписание занятий и изменения всегда под рукой.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Начать") {
                step = 1
                Task { await loadCategories() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private var chooseGroup: some View {
        VStack(spacing: 12) {
            if testMode {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Тестовый режим")
                            .font(.subheadline.bold())
                        Text("Сайт ОмАВИАТ сейчас недоступен. Показываю демонстрационные группы и данные.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Найти группу", text: $query)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)

            if categories.isEmpty && isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Загружаю список корпусов…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, categories.isEmpty {
                ContentUnavailableView {
                    Label("Не удалось получить список", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Повторить") { Task { await loadCategories(forceLive: true) } }
                        .buttonStyle(.borderedProminent)
                    Button("Открыть тестовый режим") { activateTestMode() }
                        .buttonStyle(.bordered)
                }
            } else {
                List {
                    ForEach(categories) { category in
                        Section {
                            if chosenCategory?.id == category.id {
                                ForEach(filteredGroups) { group in
                                    Button {
                                        chosenGroup = group
                                    } label: {
                                        HStack {
                                            Text(group.name).foregroundStyle(.primary)
                                            Spacer()
                                            if chosenGroup?.id == group.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.accentColor)
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
            }

            if let chosenGroup {
                Button("Продолжить · \(chosenGroup.name)") { step = 2 }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .task {
            if categories.isEmpty { await loadCategories() }
        }
    }

    private var filteredGroups: [StudentGroup] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return groups }
        return groups.filter { normalize($0.name).contains(normalizedQuery) }
    }

    private var notifications: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text("Узнавайте об изменениях сразу")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Мы сообщим, если для \(chosenGroup?.name ?? "вашей группы") появятся замены или отмены занятий.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if testMode {
                Label("В тестовом режиме используются демонстрационные изменения", systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Включить уведомления") {
                Task {
                    _ = await app.notifications.requestAuthorization()
                    finish()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            Button("Позже", action: finish).frame(maxWidth: .infinity)
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

        do {
            let loaded = try await app.scheduleService.loadCategories()
            guard !loaded.isEmpty else {
                activateTestMode()
                return
            }
            categories = loaded
            if forceLive || testMode { testMode = false }
        } catch {
            self.error = error.localizedDescription
            // No usable categories means the real app cannot continue. Fall back automatically.
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
        }
    }

    private func normalize(_ value: String) -> String {
        value.filter { $0.isLetter || $0.isNumber }.uppercased()
    }
}
