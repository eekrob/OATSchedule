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
    @State private var isLoadingCategories = false
    @State private var isLoadingGroups = false
    @State private var categoryError: String?
    @State private var groupsError: String?

    private let requestTimeout: TimeInterval = 8

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 { welcome }
                else if step == 1 { chooseGroup }
                else { notifications }
            }
            .navigationTitle(step == 1 ? "Выбор группы" : "")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.blue)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(LinearGradient(colors: [.blue.opacity(0.18), .cyan.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 230, height: 230)
                Image(systemName: "cloud.fill").font(.system(size: 42)).foregroundStyle(.blue.opacity(0.12)).offset(x: -72, y: -44)
                Image(systemName: "airplane").font(.system(size: 92, weight: .medium)).rotationEffect(.degrees(-12)).symbolRenderingMode(.palette).foregroundStyle(.blue, .cyan)
            }
            Text("ОмАВИАТ\nРасписание").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Расписание занятий и изменения всегда под рукой.").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button("Начать") {
                step = 1
                Task { await loadCategories() }
            }
            .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }.padding(24)
    }

    private var chooseGroup: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button {
                            withAnimation(.snappy) { step = 0 }
                        } label: {
                            Label("Назад", systemImage: "chevron.left").labelStyle(.iconOnly)
                                .font(.headline).frame(width: 40, height: 40)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                        }
                        Spacer()
                        if isLoadingCategories && !categories.isEmpty { ProgressView().controlSize(.small) }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Какая у вас группа?").font(.title2.bold())
                        Text("Выберите корпус и найдите свою группу.").font(.subheadline).foregroundStyle(.secondary)
                    }

                    searchField

                    if let categoryError, categories.isEmpty {
                        errorCard(title: "Список корпусов недоступен", message: categoryError) {
                            Task { await loadCategories() }
                        }
                    } else if categories.isEmpty && isLoadingCategories {
                        ProgressView("Загружаем список корпусов…")
                            .frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if !categories.isEmpty {
                        if let categoryError {
                            inlineError(categoryError) { Task { await loadCategories() } }
                        }
                        VStack(spacing: 10) {
                            ForEach(categories) { category in categoryCard(category) }
                        }
                    }

                    if let chosenCategory {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(chosenCategory.title.uppercased())
                                .font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
                                .padding(.leading, 4)

                            if let groupsError, groups.isEmpty {
                                errorCard(title: "Не удалось загрузить группы", message: groupsError) {
                                    Task { await loadGroups(in: chosenCategory) }
                                }
                            } else if groups.isEmpty && isLoadingGroups {
                                ProgressView("Загружаем группы…")
                                    .frame(maxWidth: .infinity).padding(22)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                            } else if filteredGroups.isEmpty {
                                Text(query.isEmpty ? "В этом корпусе нет опубликованных групп." : "Ничего не найдено. Проверьте запрос.")
                                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(filteredGroups) { group in
                                        Button { withAnimation(.snappy) { chosenGroup = group } } label: {
                                            HStack {
                                                Text(group.name).font(.body).foregroundStyle(.primary)
                                                Spacer()
                                                if chosenGroup?.id == group.id {
                                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                                }
                                            }.padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                        if group.id != filteredGroups.last?.id { Divider().padding(.leading, 16) }
                                    }
                                }
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                            }
                            if groupsError != nil && !groups.isEmpty {
                                inlineError(groupsError ?? "Не удалось обновить список.") {
                                    Task { await loadGroups(in: chosenCategory) }
                                }
                            } else if isLoadingGroups && !groups.isEmpty {
                                Label("Обновляем сохранённый список…", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))

            if let chosenGroup {
                Button("Продолжить · \(chosenGroup.name)") { step = 2 }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                    .background(.bar)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.body.weight(.medium)).foregroundStyle(.secondary)
            TextField("Найти группу", text: $query)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                .buttonStyle(.plain).accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 15).frame(height: 52)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17))
    }

    private func categoryCard(_ category: CollegeCategory) -> some View {
        VStack(spacing: 0) {
            Button {
                guard chosenCategory?.id != category.id else {
                    withAnimation(.snappy) { chosenCategory = nil; groups = []; chosenGroup = nil }
                    return
                }
                Task { await select(category) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.title3).foregroundStyle(.blue)
                        .frame(width: 38, height: 38).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    Text(category.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: chosenCategory?.id == category.id ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }.padding(13).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var filteredGroups: [StudentGroup] {
        guard !query.isEmpty else { return groups }
        return groups.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var notifications: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "bell.badge.fill").font(.system(size: 64)).foregroundStyle(.orange)
            Text("Узнавайте об изменениях сразу").font(.title2.bold()).multilineTextAlignment(.center)
            Text("Мы сообщим, если для \(chosenGroup?.name ?? "вашей группы") появятся замены или отмены занятий.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button("Включить уведомления") {
                Task { _ = await app.notifications.requestAuthorization(); finish() }
            }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            Button("Позже", action: finish).frame(maxWidth: .infinity)
        }.padding(24)
    }

    private func errorCard(title: String, message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 30)).foregroundStyle(.orange)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: retry) {
                Label("Повторить", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.borderedProminent).padding(.top, 2)
        }
        .padding(20).frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private func inlineError(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Button("Повторить", action: retry).font(.caption.weight(.semibold))
        }.padding(12).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private func finish() {
        guard let category = chosenCategory, let group = chosenGroup else { return }
        onComplete(UserSelection(category: category, group: group))
    }

    private func loadCategories() async {
        guard !isLoadingCategories else { return }
        if categories.isEmpty, let cached = app.store.read([CollegeCategory].self, key: "onboarding|categories"), !cached.isEmpty {
            categories = cached
            if let chosenCategory, let refreshed = cached.first(where: { $0.id == chosenCategory.id }) { self.chosenCategory = refreshed }
        }
        categoryError = nil
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        do {
            let fresh = try await app.scheduleService.loadCategories(timeout: requestTimeout)
            categories = fresh
            app.store.write(fresh, key: "onboarding|categories")
            if let chosenCategory, let refreshed = fresh.first(where: { $0.id == chosenCategory.id }) { self.chosenCategory = refreshed }
            else if chosenCategory != nil { self.chosenCategory = nil; groups = []; chosenGroup = nil }
        } catch {
            categoryError = error.localizedDescription
        }
    }

    private func select(_ category: CollegeCategory) async {
        chosenCategory = category
        chosenGroup = nil
        query = ""
        groupsError = nil
        groups = app.store.read([StudentGroup].self, key: groupsCacheKey(category)) ?? []
        await loadGroups(in: category)
    }

    private func loadGroups(in category: CollegeCategory) async {
        guard !isLoadingGroups else { return }
        if groups.isEmpty, let cached = app.store.read([StudentGroup].self, key: groupsCacheKey(category)) { groups = cached }
        groupsError = nil
        isLoadingGroups = true
        defer { isLoadingGroups = false }
        do {
            let fresh = try await app.scheduleService.loadGroups(in: category, timeout: requestTimeout)
            groups = fresh
            app.store.write(fresh, key: groupsCacheKey(category))
        } catch {
            groupsError = error.localizedDescription
        }
    }

    private func groupsCacheKey(_ category: CollegeCategory) -> String { "onboarding|groups|\(category.id)" }
}
