import SwiftUI

@main
@MainActor
struct VesperCoachApp: App {
    @StateObject private var coach = Coach()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                BoardWebView().tabItem { Label("Шахматы", systemImage: "checkerboard.rectangle") }
                CoachView(coach: coach).tabItem { Label("Захват", systemImage: "rectangle.inset.filled.and.person.filled") }
            }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { coach.becameActive() }
                }
        }
    }
}

struct CoachView: View {
    @ObservedObject var coach: Coach
    @State private var selection: CGRect?
    @State private var origin: CGPoint?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(coach.message)
                    if let hint = coach.lastHint {
                        Text(hint).font(.title2.monospacedDigit()).bold()
                    }
                    if let clock = coach.clockText { Text(clock).font(.footnote.monospacedDigit()) }
                    if !coach.capturing {
                        Picker("Моя сторона", selection: $coach.player) {
                            Text("Играю белыми").tag("w")
                            Text("Играю чёрными").tag("b")
                        }.pickerStyle(.segmented)
                        VStack(alignment: .leading, spacing: 8) {
                            let modes = ["Instant · 1 мин", "Medium · 3 мин", "Hard · 10 мин"]
                            Text(modes[coach.pace]).font(.headline)
                            Slider(value: Binding(get: { Double(coach.pace) },
                                                  set: { coach.pace = Int($0) }), in: 0...2, step: 1)
                                .accessibilityLabel("Темп партии")
                                .accessibilityValue(modes[coach.pace])
                        }
                        Toggle("Автопоиск доски Chess.com", isOn: $coach.useChessComProfile)
                    }
                    if let snapshot = coach.snapshot, let image = snapshot.image {
                        Picker("Цвет снизу", selection: $coach.whiteAtBottom) {
                            Text("Белые").tag(true)
                            Text("Чёрные").tag(false)
                        }.pickerStyle(.segmented)
                        snapshotView(snapshot, image: image)
                        Button("Отслеживать") {
                            if let selection { coach.setCalibration(selection) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selection == nil)
                    }

                    if coach.capturing {
                        HStack {
                            Button("Выбрать доску заново") { selection = nil; coach.retake() }
                            Spacer()
                            Button("Стоп", role: .destructive) {
                                selection = nil
                                Task { await coach.stop() }
                            }
                        }
                    } else {
                        Button("Начать захват экрана") { coach.chooseScreen() }
                            .buttonStyle(.borderedProminent)
                            .disabled(coach.choosing)
                    }
                }
                .padding()
            }
            .navigationTitle("Vesper Gambit")
        }
    }

    private func snapshotView(_ frame: Frame, image: CGImage) -> some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / CGFloat(frame.width)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                if let rect = selection {
                    Rectangle().strokeBorder(.green, lineWidth: 2)
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .offset(x: rect.minX * scale, y: rect.minY * scale)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let from = origin ?? drag.startLocation
                    origin = from
                    let to = drag.location
                    let size = geometry.size
                    let lowX = max(0, min(size.width, min(from.x, to.x)))
                    let lowY = max(0, min(size.height, min(from.y, to.y)))
                    let highX = max(0, min(size.width, max(from.x, to.x)))
                    let highY = max(0, min(size.height, max(from.y, to.y)))
                    selection = CGRect(x: lowX / scale, y: lowY / scale,
                                       width: (highX - lowX) / scale, height: (highY - lowY) / scale)
                }
                .onEnded { _ in origin = nil })
            .accessibilityLabel("Снимок. Выделите границы шахматной доски.")
        }
        .aspectRatio(CGFloat(frame.width) / CGFloat(frame.height), contentMode: .fit)
    }
}
