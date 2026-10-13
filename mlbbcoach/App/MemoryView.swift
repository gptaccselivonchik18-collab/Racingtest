import SwiftUI
import SwiftData

struct MemoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MemoryEntry.created, order: .reverse) private var entries: [MemoryEntry]
    @State private var search = ""
    @State private var adding = false
    @State private var editing: MemoryEntry?
    @State private var error: String?
    private var filtered: [MemoryEntry] { entries.filter { search.isEmpty || "\($0.text) \($0.hero) \($0.role)".localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            Section { Text("Память влияет на контекст тренера. Заметки не изменяют веса нейросети.").font(.caption).foregroundStyle(.secondary) }
            if filtered.isEmpty { ContentUnavailableView("Нет записей", systemImage: "brain") }
            ForEach(filtered) { entry in
                Button { editing = entry } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(entry.kind).font(.caption).foregroundStyle(.mint); Spacer(); if !entry.enabled { Image(systemName: "pause.circle") } }
                        Text(entry.text).foregroundStyle(.primary).lineLimit(4)
                        Text([entry.hero, entry.role, entry.patch].filter { !$0.isEmpty }.joined(separator: " • ")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }.onDelete { offsets in
                for index in offsets { context.delete(filtered[index]) }
                do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
            }
            if let error { Text(error).foregroundStyle(.orange) }
        }.navigationTitle("Память").searchable(text: $search)
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Добавить запись") }
        .sheet(isPresented: $adding) { NavigationStack { MemoryEditor() } }
        .sheet(item: $editing) { entry in NavigationStack { MemoryEditor(entry: entry) } }
    }
}
struct MemoryEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let entry: MemoryEntry?
    @State private var text: String
    @State private var kind: String
    @State private var hero: String
    @State private var role: String
    @State private var patch: String
    @State private var source: String
    @State private var enabled: Bool
    @State private var error: String?
    init(entry: MemoryEntry? = nil, initialText: String = "") {
        self.entry = entry
        _text = State(initialValue: entry?.text ?? initialText); _kind = State(initialValue: entry?.kind ?? "Предпочтение")
        _hero = State(initialValue: entry?.hero ?? ""); _role = State(initialValue: entry?.role ?? "")
        _patch = State(initialValue: entry?.patch ?? ""); _source = State(initialValue: entry?.source ?? "")
        _enabled = State(initialValue: entry?.enabled ?? true)
    }
    var body: some View {
        Form {
            TextEditor(text: $text).frame(minHeight: 140).accessibilityLabel("Содержание записи")
            Picker("Тип", selection: $kind) { ForEach(MemoryKind.all, id: \.self) { Text($0) } }
            TextField("Герой", text: $hero); TextField("Роль", text: $role); TextField("Версия патча", text: $patch)
            TextField("Ссылка на источник", text: $source).textInputAutocapitalization(.never).keyboardType(.URL)
            Toggle("Использовать в контексте", isOn: $enabled)
            Text("Источник не делает запись автоматически проверенным фактом. Противоречия проверяются по версии патча.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange) }
        }.navigationTitle(entry == nil ? "Новая память" : "Редактирование")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }
    private func save() {
        if kind == "Факт с источником", URL(string: source)?.scheme != "https" { error = "Для факта нужна HTTPS-ссылка на источник."; return }
        let item = entry ?? MemoryEntry(text: text)
        if entry == nil { context.insert(item) }
        item.text = text.trimmingCharacters(in: .whitespacesAndNewlines); item.kind = kind
        item.hero = hero; item.role = role; item.patch = patch; item.source = source; item.enabled = enabled
        do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
