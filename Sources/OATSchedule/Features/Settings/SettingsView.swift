import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var app
    let selection: UserSelection
    @State private var notificationEnabled = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Моя группа") {
                    LabeledContent("Группа", value: selection.group.name)
                    LabeledContent("Корпус", value: selection.category.title)
                    Button("Изменить группу") {
                        app.store.remove(key: "selection")
                        NotificationCenter.default.post(name: .resetSelection, object: nil)
                    }
                        .foregroundStyle(.red)
                }
                Section("Уведомления") {
                    Button(notificationEnabled ? "Разрешение запрошено" : "Включить уведомления") {
                        Task { notificationEnabled = await app.notifications.requestAuthorization() }
                    }.disabled(notificationEnabled)
                    Text("Обновление выполняется при открытии приложения или вручную. Для push в фоне нужен серверный backend.")
                        .font(.footnote).foregroundStyle(.secondary)
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

