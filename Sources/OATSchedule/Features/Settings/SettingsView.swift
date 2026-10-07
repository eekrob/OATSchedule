import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppContainer.self) private var app
    let selection: UserSelection

    @State private var notificationEnabled = false
    @State private var diagnosticCopied = false
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("testMode") private var testMode = false

    var body: some View {
        NavigationStack {
            ZStack {
                OATAppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sectionTitle("Моя группа")
                        groupCard

                        if testMode {
                            sectionTitle("Тестовый режим")
                            diagnosticsCard
                        }

                        sectionTitle("Уведомления")
                        VStack(spacing: 0) {
                            notificationRow(
                                "Изменения расписания",
                                subtitle: "Новые замены и переносы",
                                isOn: $notificationEnabled
                            )
                        }
                        .oatGlassSurface(radius: 20, interactive: true)

                        sectionTitle("Оформление")
                        VStack(spacing: 0) {
                            ForEach(AppearanceMode.Value.allCases) { mode in
                                Button {
                                    withAnimation(.snappy) {
                                        appearance = mode.rawValue
                                    }
                                } label: {
                                    HStack {
                                        Text(mode.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        if appearance == mode.rawValue {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(OATTheme.blue)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 52)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if mode.id != AppearanceMode.Value.allCases.last?.id {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .oatGlassSurface(radius: 20, interactive: true)

                        sectionTitle("О приложении")
                        VStack(alignment: .leading, spacing: 15) {
                            Link(destination: URL(string: "https://www.oat.ru/timetable/Classes")!) {
                                Label("Официальное расписание oat.ru", systemImage: "safari")
                            }

                            Link(destination: URL(string: "https://www.oat.ru/timetable/ClassesChanges")!) {
                                Label("Изменения расписания", systemImage: "arrow.triangle.2.circlepath")
                            }

                            Divider()

                            HStack {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundStyle(OATTheme.blue)
                                Text("ОмАВИАТ Расписание")
                                Spacer()
                                Text("1.0")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                        .tint(OATTheme.blue)
                        .padding(16)
                        .oatGlassSurface(radius: 20)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var groupCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "airplane")
                .font(.title2)
                .foregroundStyle(OATTheme.blue)
                .frame(width: 50, height: 50)
                .oatGlassSurface(radius: 16, tint: OATTheme.blue.opacity(0.08))

            VStack(alignment: .leading, spacing: 4) {
                Text(selection.group.name)
                    .font(.headline)
                Text(selection.category.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button("Изменить") {
                app.store.remove(key: "selection")
                NotificationCenter.default.post(name: .resetSelection, object: nil)
            }
            .font(.subheadline.weight(.medium))
            .oatGlassButton()
        }
        .padding(16)
        .oatGlassSurface(radius: 20, interactive: true)
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Используются демонстрационные данные", systemImage: "wrench.and.screwdriver.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)

            Text("Скопируйте технический отчёт и отправьте его разработчику — в нём есть HTTP-код, итоговый URL, размер ответа и фрагмент HTML. Значения cookies скрыты.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                copyDiagnostics()
            } label: {
                Label(
                    diagnosticCopied ? "Диагностика скопирована" : "Скопировать диагностику",
                    systemImage: diagnosticCopied ? "checkmark" : "doc.on.doc"
                )
                .frame(maxWidth: .infinity)
            }
            .oatGlassButton(prominent: true)
            .tint(.orange)
        }
        .padding(16)
        .oatGlassSurface(radius: 20, tint: .orange.opacity(0.08))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.bottom, -14)
    }

    private func notificationRow(
        _ title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(OATTheme.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .onChange(of: isOn.wrappedValue) { _, enabled in
                    if enabled {
                        Task {
                            notificationEnabled = await app.notifications.requestAuthorization()
                        }
                    }
                }
        }
        .padding(16)
    }

    private func copyDiagnostics() {
        Task {
            let report = await NetworkDiagnosticsStore.shared.report()
            await MainActor.run {
                UIPasteboard.general.string = report
                diagnosticCopied = true
            }

            try? await Task.sleep(for: .seconds(1.5))

            await MainActor.run {
                diagnosticCopied = false
            }
        }
    }
}
