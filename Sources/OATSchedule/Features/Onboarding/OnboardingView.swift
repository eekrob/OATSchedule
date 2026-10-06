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
                Circle().fill(LinearGradient(colors: [.blue.opacity(0.18), .cyan.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 230, height: 230)
                Image(systemName: "cloud.fill").font(.system(size: 42)).foregroundStyle(.blue.opacity(0.12)).offset(x: -72, y: -44)
                Image(systemName: "airplane").font(.system(size: 92, weight: .medium)).rotationEffect(.degrees(-12)).symbolRenderingMode(.palette).foregroundStyle(.blue, .cyan)
            }
            Text("ОмАВИАТ\nРасписание").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Расписание занятий и изменения всегда под рукой.").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button("Начать") { step = 1; Task { await loadCategories() } }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }.padding(24)
    }

    private var chooseGroup: some View {
        VStack(spacing: 12) {
            TextField("Найти группу", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal)
            if categories.isEmpty && isLoading { ProgressView("Загружаю список корпусов…") }
            if let error { ContentUnavailableView("Не удалось получить список", systemImage: "wifi.exclamationmark", description: Text(error)) }
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
                                        if chosenGroup?.id == group.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                                    }.contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Button { Task { await select(category) } } label: {
                            HStack { Text(category.title); Spacer(); Image(systemName: chosenCategory?.id == category.id ? "chevron.down" : "chevron.right") }
                        }.foregroundStyle(.primary)
                    }
                }
            }.listStyle(.insetGrouped)
            if let chosenGroup {
                Button("Продолжить · \(chosenGroup.name)") { step = 2 }
                    .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal)
            }
        }
        .task { if categories.isEmpty { await loadCategories() } }
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

    private func finish() {
        guard let category = chosenCategory, let group = chosenGroup else { return }
        onComplete(UserSelection(category: category, group: group))
    }
    private func loadCategories() async {
        isLoading = true; defer { isLoading = false }
        do { categories = try await app.scheduleService.loadCategories() }
        catch { self.error = error.localizedDescription }
    }
    private func select(_ category: CollegeCategory) async {
        chosenCategory = category; chosenGroup = nil; groups = []; isLoading = true; defer { isLoading = false }
        do { groups = try await app.scheduleService.loadGroups(in: category) }
        catch { self.error = error.localizedDescription }
    }
}

