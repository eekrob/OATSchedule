import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var app
    let selection: UserSelection
    @State private var notificationEnabled = false
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.3.fill").font(.title2).foregroundStyle(.blue)
                            .frame(width: 48, height: 48).background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selection.group.name).font(.title3.bold())
                            Text(selection.category.title).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.padding(.vertical, 5)
                    Button("Изменить группу") {
                        app.store.remove(key: "selection")
                        NotificationCenter.default.post(name: .resetSelection, object: nil)
                    }
                        .foregroundStyle(.red)
                }
                Section("Уведомления") {
                    Toggle("Изменения расписания", isOn: $notificationEnabled)
                        .onChange(of: notificationEnabled) { _, enabled in
                            if enabled { Task { notificationEnabled = await app.notifications.requestAuthorization() } }
                        }
                    Text("Проверка изменений выполняется при открытии приложения и вручную.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Оформление") {
                    Picker("Тема", selection: $appearance) {
                        ForEach(AppearanceMode.Value.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Источник и приложение") {
                    Link("Официальное расписание oat.ru", destination: URL(string: "https://www.oat.ru/timetable/Classes")!)
                    Link("Изменения расписания", destination: URL(string: "https://www.oat.ru/timetable/ClassesChanges")!)
                    Text("ОмАВИАТ Расписание · версия 1.0")
                }
            }.navigationTitle("Настройки")
        }
    }
}

