import SwiftUI
import UIKit

struct ChapterReaderView: View {
    let chapterId: Int
    /// Path from book through parent sections (not including the leaf chapter title).
    var breadcrumbTitles: [String] = []
    /// Row title before the chapter API responds.
    var listContextTitle: String = ""

    @State private var detail: ChapterDetailResponse?
    @State private var loadError: Error?
    @State private var isLoading = true
    @State private var topTab: ReaderTopTab = .layers
    @StateObject private var recordingsStore: LocalRecordingsStore
    @StateObject private var recorder = AudioRecorderController()
    @State private var recordingsSheetPresented = false
    @State private var listNudgeToken: Int = 0
    @State private var micAlertPresented = false

    @State private var layerQuizzes: [LayerQuiz] = []
    @State private var quizzesLoading = false
    @State private var quizzesErrorMessage: String?
    @State private var activeQuiz: LayerQuiz?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isLoadingMoreItems = false
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @State private var paywallPresented = false
    /// When set, layer items show matching `sub_layer_items` body/hint when present.
    @State private var selectedSublayerName: String?

    init(chapterId: Int, breadcrumbTitles: [String] = [], listContextTitle: String = "") {
        self.chapterId = chapterId
        self.breadcrumbTitles = breadcrumbTitles
        self.listContextTitle = listContextTitle
        _recordingsStore = StateObject(wrappedValue: LocalRecordingsStore(chapterId: chapterId))
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading chapter…")
                    .tint(AppTheme.forestGreen)
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn’t load chapter",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError.localizedDescription)
                )
            } else if let detail {
                if shouldGatePremiumContent(detail) {
                    premiumLockedScreen()
                } else {
                    VStack(spacing: 0) {
                        ReaderTopTabs(selected: $topTab)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(topTabsBackground)

                        if topTab == .record {
                            RecordControlsRow(
                                isRecording: recorder.state == .recording,
                                listNudgeToken: $listNudgeToken,
                                onToggleRecording: {
                                    recorder.toggleRecording { saved in
                                        recordingsStore.add(saved, chapterId: chapterId)
                                        listNudgeToken += 1
                                    }
                                },
                                onOpenList: { recordingsSheetPresented = true }
                            )
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 6)
                                .background(screenBackground)
                            if recorder.state == .recording {
                                LiveWaveformRow(samples: recorder.liveWaveform)
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 6)
                            }
                        } else if topTab == .quiz {
                            QuizControlsRow(
                                isLoading: quizzesLoading,
                                hasQuiz: quizHasQuestions,
                                errorMessage: quizzesErrorMessage,
                                onStartQuiz: { startQuizIfAvailable() }
                            )
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 6)
                                .background(screenBackground)
                        }

                        // Always keep the chapter visible + scrollable under the fixed rows.
                        chapterBodyContent(detail)
                            .environment(\.layoutDirection, contentLayoutDirection(for: detail.language))
                            .padding(.top, 4)
                    }
                }
            } else {
                ContentUnavailableView("Nothing to read", systemImage: "doc.text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(screenBackground)
        .fushaNavigationTitle(ancestors: breadcrumbTitles, title: navigationBarTitle)
        .onChange(of: recorder.state) { _, newValue in
            if newValue == .permissionDenied {
                micAlertPresented = true
            }
        }
        .alert("Microphone Access Needed", isPresented: $micAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable microphone access for Fusha Nation in Settings to record your recitation.")
        }
        .sheet(isPresented: $recordingsSheetPresented) {
            NavigationStack {
                RecordingsListView(store: recordingsStore)
                    .navigationTitle("Recordings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { recordingsSheetPresented = false }
                        }
                    }
            }
        }
        .sheet(item: $activeQuiz) { quiz in
            QuizModalView(quiz: quiz)
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallView()
                .environmentObject(subscriptionStore)
        }
        .task(id: chapterId) {
            await load()
        }
        .onChange(of: topTab) { _, newTab in
            guard newTab == .quiz else { return }
            Task { await loadQuizzesForDefaultLayerIfNeeded() }
        }
    }

    private func shouldGatePremiumContent(_ detail: ChapterDetailResponse) -> Bool {
        if detail.viewerIsAdmin == true { return false }
        return detail.chapter.isPremiumTier && !subscriptionStore.isSubscribed
    }

    @ViewBuilder
    private func premiumLockedScreen() -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.forestGreen)
            Text("Premium chapter")
                .font(.title2.bold())
                .foregroundStyle(colorScheme == .dark ? .white : AppTheme.textPrimary)
            Text("Subscribe to read this lesson and unlock all premium content.")
                .font(.body)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.75) : AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                paywallPresented = true
            } label: {
                Text("View subscription")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.forestGreen)
            .padding(.horizontal, 32)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(screenBackground)
    }

    private var navigationBarTitle: String {
        if let d = detail {
            let t = d.chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        let ctx = listContextTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ctx.isEmpty { return ctx }
        return "Chapter"
    }

    private func contentLayoutDirection(for language: LanguageInfo) -> LayoutDirection {
        (language.direction ?? "ltr").lowercased() == "rtl" ? .rightToLeft : .leftToRight
    }

    @ViewBuilder
    private func chapterBodyContent(_ detail: ChapterDetailResponse) -> some View {
        let mode = (detail.chapter.chapterMode ?? "text").lowercased()
        if mode == "images" {
            ImageChapterReadView(chapterId: detail.chapter.id, chapterImages: detail.chapterImages ?? [])
        } else if mode == "text" {
            defaultLayerScroll(detail)
        } else {
            ContentUnavailableView(
                "Unsupported chapter mode",
                systemImage: "exclamationmark.triangle",
                description: Text("This chapter mode is not supported yet.")
            )
            .task {
                #if DEBUG
                print("⚠️ Unsupported chapter mode:", mode)
                #endif
            }
        }
    }

    @ViewBuilder
    private func defaultLayerScroll(_ detail: ChapterDetailResponse) -> some View {
        if let layer = Self.pickDefaultLayer(from: detail.chapterLayers) {
            ScrollView {
                DefaultLayerContentView(items: layer.chapterLayerItems)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(readerCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(readerCardStroke, lineWidth: 1)
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
            }
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView(
                "No layer",
                systemImage: "square.stack",
                description: Text("This chapter has no active content layer.")
            )
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? Color(white: 0.08) : AppTheme.background
    }

    private var topTabsBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : AppTheme.bannerPink.opacity(0.9)
    }

    private var readerCardBackground: Color {
        colorScheme == .dark ? Color(white: 0.13) : AppTheme.readerCard
    }

    private var readerCardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : AppTheme.readerCardStroke
    }

    private func load() async {
        isLoading = true
        isLoadingMoreItems = false
        loadError = nil
        do {
            let firstPageSize = 40
            var merged = try await ChapterAPI.fetchChapterDetail(
                id: chapterId,
                itemsPerPage: firstPageSize,
                itemsPage: 1
            )
            detail = merged
            isLoading = false

            // Continue paging in background for heavy chapters.
            isLoadingMoreItems = true
            var page = 2
            let maxFollowupPages = 24
            while !Task.isCancelled, page <= maxFollowupPages {
                let next = try await ChapterAPI.fetchChapterDetail(
                    id: chapterId,
                    itemsPerPage: firstPageSize,
                    itemsPage: page
                )
                let beforeCount = Self.totalLayerItemCount(in: merged)
                let combined = Self.mergedChapterDetail(base: merged, incoming: next)
                let afterCount = Self.totalLayerItemCount(in: combined)
                let added = afterCount - beforeCount

                if added <= 0 {
                    break
                }

                merged = combined
                detail = merged
                page += 1
            }
            isLoadingMoreItems = false
        } catch {
            loadError = error
            detail = nil
            isLoadingMoreItems = false
            isLoading = false
            return
        }
        isLoading = false
    }

    private static func pickDefaultLayer(from layers: [ChapterLayer]) -> ChapterLayer? {
        let active = layers.filter(\.active).sorted { $0.position < $1.position }
        if let def = active.first(where: \.isDefault) { return def }
        return active.first
    }

    private static func totalLayerItemCount(in detail: ChapterDetailResponse) -> Int {
        detail.chapterLayers.reduce(0) { $0 + $1.chapterLayerItems.count }
    }

    private static func mergedChapterDetail(base: ChapterDetailResponse, incoming: ChapterDetailResponse) -> ChapterDetailResponse {
        let mergedLayers = mergeLayers(base.chapterLayers, incoming.chapterLayers)
        return ChapterDetailResponse(
            chapter: base.chapter,
            chapterImages: base.chapterImages ?? incoming.chapterImages,
            language: base.language,
            chapterLayers: mergedLayers,
            itemsLayerId: base.itemsLayerId ?? incoming.itemsLayerId,
            itemsPage: incoming.itemsPage ?? base.itemsPage,
            itemsPerPage: incoming.itemsPerPage ?? base.itemsPerPage,
            viewerIsAdmin: base.viewerIsAdmin
        )
    }

    private static func mergeLayers(_ left: [ChapterLayer], _ right: [ChapterLayer]) -> [ChapterLayer] {
        var byID: [Int: ChapterLayer] = Dictionary(uniqueKeysWithValues: left.map { ($0.id, $0) })
        for layer in right {
            if let existing = byID[layer.id] {
                let mergedItems = mergeLayerItems(existing.chapterLayerItems, layer.chapterLayerItems)
                byID[layer.id] = ChapterLayer(
                    id: existing.id,
                    title: existing.title,
                    active: existing.active,
                    isDefault: existing.isDefault,
                    position: existing.position,
                    chapterLayerItemsCount: layer.chapterLayerItemsCount ?? existing.chapterLayerItemsCount,
                    chapterLayerItemsHasMore: layer.chapterLayerItemsHasMore ?? existing.chapterLayerItemsHasMore,
                    chapterLayerItems: mergedItems
                )
            } else {
                byID[layer.id] = layer
            }
        }
        return byID.values.sorted { $0.position < $1.position }
    }

    private static func mergeLayerItems(_ left: [ChapterLayerItem], _ right: [ChapterLayerItem]) -> [ChapterLayerItem] {
        var map: [Int: ChapterLayerItem] = Dictionary(uniqueKeysWithValues: left.map { ($0.id, $0) })
        for item in right {
            if let existing = map[item.id] {
                map[item.id] = mergeTwoLayerItems(existing, item)
            } else {
                map[item.id] = item
            }
        }
        return map.values.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.id < $1.id
        }
    }

    private static func mergeTwoLayerItems(_ existing: ChapterLayerItem, _ incoming: ChapterLayerItem) -> ChapterLayerItem {
        var subById: [Int: ChapterSubLayerItem] = Dictionary(uniqueKeysWithValues: existing.subLayerItems.map { ($0.id, $0) })
        for s in incoming.subLayerItems {
            subById[s.id] = s
        }
        let mergedSubs = subById.values.sorted { $0.id < $1.id }
        return ChapterLayerItem(
            id: incoming.id,
            chapterLayerId: incoming.chapterLayerId,
            body: incoming.body,
            style: incoming.style,
            hint: incoming.hint,
            position: incoming.position,
            subLayerItems: mergedSubs
        )
    }

    private var quizHasQuestions: Bool {
        let sorted = layerQuizzes
        for q in sorted {
            if !q.layerQuizQuestions.isEmpty { return true }
        }
        return false
    }

    private func loadQuizzesForDefaultLayerIfNeeded() async {
        guard let detail else { return }
        guard let layer = Self.pickDefaultLayer(from: detail.chapterLayers) else { return }
        // If we've already loaded for this layer, keep the existing state.
        if layerQuizzes.first?.chapterLayerId == layer.id { return }

        quizzesLoading = true
        quizzesErrorMessage = nil
        layerQuizzes = []
        do {
            layerQuizzes = try await ChapterAPI.fetchLayerQuizzes(chapterLayerId: layer.id)
            #if DEBUG
            let totalQuestions = layerQuizzes.reduce(0) { $0 + $1.layerQuizQuestions.count }
            print("✅ layer quizzes loaded for chapter_layer_id=\(layer.id) quizzes=\(layerQuizzes.count) questions=\(totalQuestions)")
            #endif
        } catch {
            quizzesErrorMessage = error.localizedDescription
            #if DEBUG
            print("⚠️ layer quizzes failed for chapter_layer_id=\(layer.id): \(error)")
            #endif
        }
        quizzesLoading = false
    }

    private func startQuizIfAvailable() {
        guard quizHasQuestions else {
            quizzesErrorMessage = "No quiz available"
            return
        }
        guard let picked = pickPreferredQuiz(from: layerQuizzes) else {
            quizzesErrorMessage = "No quiz available"
            return
        }
        #if DEBUG
        print("🎮 start quiz tapped: picked quiz id=\(picked.id) title=\(picked.title ?? "<nil>") questions=\(picked.layerQuizQuestions.count)")
        #endif
        activeQuiz = picked
    }

    private func pickPreferredQuiz(from quizzes: [LayerQuiz]) -> LayerQuiz? {
        let nonEmpty = quizzes.filter { !$0.layerQuizQuestions.isEmpty }
        if let mcq = nonEmpty.first(where: { ($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mcq" }) {
            return mcq
        }
        return nonEmpty.first
    }
}

private enum ReaderTopTab: String, CaseIterable, Identifiable {
    case layers = "Layers"
    case record = "Record"
    case quiz = "Quiz"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .layers: return "square.3.layers.3d"
        case .record: return "mic.fill"
        case .quiz: return "gamecontroller.fill"
        }
    }
}

private struct ReaderTopTabs: View {
    @Binding var selected: ReaderTopTab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ReaderTopTab.allCases) { tab in
                Button {
                    selected = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.systemImage)
                            .imageScale(.medium)
                        Text(tab.rawValue)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(isActive(tab) ? Color.white : AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isActive(tab) ? AppTheme.forestGreen : inactiveTabBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func isActive(_ tab: ReaderTopTab) -> Bool { selected == tab }

    private var inactiveTabBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.6)
    }
}

private struct RecordControlsRow: View {
    let isRecording: Bool
    @Binding var listNudgeToken: Int
    let onToggleRecording: () -> Void
    let onOpenList: () -> Void

    @State private var bump = false
    @State private var shakeCount: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onToggleRecording()

                // When we are currently recording, tapping means STOP + save;
                // bump the main button toward the list button.
                if isRecording {
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { bump = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) { bump = false }
                    }
                }
            } label: {
                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isRecording ? Color.red.opacity(0.85) : AppTheme.forestGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .offset(x: bump ? 10 : 0)

            Button {
                onOpenList()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 54, height: 48)
                    .background(sideButtonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .modifier(ShakeEffect(shakes: shakeCount))
        }
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: listNudgeToken) { _, _ in
            // Trigger shake after a save lands in the list.
            withAnimation(.linear(duration: 0.45)) {
                shakeCount += 1
            }
        }
    }

    private var sideButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.6)
    }
}

private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var amplitude: CGFloat = 7

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amplitude * sin(shakes * .pi * 6)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

private struct RecordingsListView: View {
    @ObservedObject var store: LocalRecordingsStore
    @StateObject private var player = AudioPlayerController()

    var body: some View {
        Group {
            if store.recordings.isEmpty {
                ContentUnavailableView("No recordings yet", systemImage: "waveform")
            } else {
                List {
                    ForEach(store.recordings) { r in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                player.togglePlay(r)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: player.currentID == r.id && player.isPlaying ? "stop.fill" : "play.fill")
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        Text(r.fileName)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if let d = r.durationSeconds {
                                        Text(Self.formatDuration(d))
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)

                            if player.currentID == r.id {
                                WaveformSeeker(
                                    samples: r.waveform ?? [],
                                    progress: player.duration > 0 ? player.currentTime / player.duration : 0,
                                    onSeek: { pct in
                                        player.seek(to: pct * player.duration)
                                    }
                                )
                                .frame(height: 44)
                            }
                        }
                        .listRowBackground(AppTheme.listRow)
                    }
                    .onDelete(perform: store.delete)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.background)
        .onDisappear { player.stop() }
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct QuizControlsRow: View {
    let isLoading: Bool
    let hasQuiz: Bool
    let errorMessage: String?
    let onStartQuiz: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading quiz…")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if hasQuiz {
                Button {
                    onStartQuiz()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gamecontroller.fill")
                            .imageScale(.medium)
                        Text("Start Quiz")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.forestGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                // Requirement: only show the game button if a quiz exists.
                // When there's no quiz, keep this area empty (history button remains).
                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                } else {
                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                }
            }

            Button {
                // Placeholder for quiz history / attempts list
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 54, height: 48)
                    .background(surfaceColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.6)
    }
}

private struct QuizModalView: View {
    let quiz: LayerQuiz
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var index: Int = 0
    @State private var selectedAnswerIDByQuestionID: [Int: Int] = [:]
    @State private var reveal: Bool = false
    @State private var shuffledAnswersByQuestionID: [Int: [LayerItemQuizAnswer]] = [:]
    @State private var shuffledQuestions: [LayerQuizQuestion] = []

    private var questions: [LayerQuizQuestion] {
        if !shuffledQuestions.isEmpty { return shuffledQuestions }
        return sortedQuestions
    }

    private func answers(for q: LayerQuizQuestion) -> [LayerItemQuizAnswer] {
        if let shuffled = shuffledAnswersByQuestionID[q.id] {
            return shuffled
        }
        let sorted = q.layerItemQuizAnswers.sorted {
            let lp = $0.position ?? Int.max
            let rp = $1.position ?? Int.max
            if lp != rp { return lp < rp }
            return $0.id < $1.id
        }
        return sorted
    }

    private var sortedQuestions: [LayerQuizQuestion] {
        quiz.layerQuizQuestions.sorted {
            let lp = $0.position ?? Int.max
            let rp = $1.position ?? Int.max
            if lp != rp { return lp < rp }
            return $0.id < $1.id
        }
    }

    private var isLast: Bool { index >= max(0, questions.count - 1) }

    var body: some View {
        NavigationStack {
            Group {
                if questions.isEmpty {
                    ContentUnavailableView("No quiz available", systemImage: "questionmark.circle")
                } else {
                    let q = questions[min(index, questions.count - 1)]
                    ScrollView {
                        VStack(alignment: .trailing, spacing: 16) {
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("Question \(index + 1) of \(questions.count)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)

                                if let original = q.original, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(original)
                                        .font(ArabicTypography.swiftUIFont(size: 34))
                                        .foregroundStyle(Color.primary)
                                        .multilineTextAlignment(.trailing)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }

                            VStack(spacing: 10) {
                                ForEach(answers(for: q)) { a in
                                    answerRow(questionID: q.id, answer: a)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(modalBackground)
            .navigationTitle((quiz.title ?? "Quiz").isEmpty ? "Quiz" : (quiz.title ?? "Quiz"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
                    .background(.ultraThinMaterial)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            // Shuffle questions + choices once per modal presentation and keep stable.
            if !shuffledQuestions.isEmpty, !shuffledAnswersByQuestionID.isEmpty { return }
            if shuffledQuestions.isEmpty {
                shuffledQuestions = sortedQuestions.shuffled()
            }
            var dict: [Int: [LayerItemQuizAnswer]] = [:]
            for q in shuffledQuestions {
                let sorted = q.layerItemQuizAnswers.sorted {
                    let lp = $0.position ?? Int.max
                    let rp = $1.position ?? Int.max
                    if lp != rp { return lp < rp }
                    return $0.id < $1.id
                }
                dict[q.id] = sorted.shuffled()
            }
            shuffledAnswersByQuestionID = dict
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if questions.isEmpty {
            EmptyView()
        } else {
            let q = questions[min(index, questions.count - 1)]
            let selected = selectedAnswerIDByQuestionID[q.id]

            VStack(spacing: 10) {
                if reveal, isLast {
                    Text(scoreLine())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        // restart
                        index = 0
                        selectedAnswerIDByQuestionID = [:]
                        reveal = false
                        // Re-shuffle on restart for a fresh attempt.
                        shuffledAnswersByQuestionID = [:]
                    } label: {
                        Text("Restart")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 96, height: 44)
                            .background(restartSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if !reveal {
                            reveal = true
                            return
                        }
                        // Next / Finish
                        if isLast {
                            return
                        }
                        index += 1
                        reveal = false
                    } label: {
                        Text(isLast ? (reveal ? "Done" : "Check") : (reveal ? "Next" : "Check"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background((selected == nil) ? Color.gray.opacity(0.4) : AppTheme.forestGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selected == nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func answerRow(questionID: Int, answer: LayerItemQuizAnswer) -> some View {
        let selectedID = selectedAnswerIDByQuestionID[questionID]
        let isSelected = selectedID == answer.id
        let isCorrect = (answer.correct ?? false)

        let bg: Color = {
            if reveal {
                if isCorrect { return Color.green.opacity(0.18) }
                if isSelected { return Color.red.opacity(0.16) }
            }
            return colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.75)
        }()

        let stroke: Color = {
            if isSelected { return AppTheme.forestGreen.opacity(0.75) }
            return colorScheme == .dark ? Color.white.opacity(0.22) : AppTheme.readerCardStroke
        }()

        Button {
            selectedAnswerIDByQuestionID[questionID] = answer.id
        } label: {
            HStack(spacing: 10) {
                // In RTL, keep the indicator on the left and text pinned right.
                indicatorView(isSelected: isSelected, reveal: reveal, isCorrect: isCorrect)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    if let o = answer.original, !o.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(o)
                            .font(ArabicTypography.swiftUIFont(size: 28))
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(reveal) // lock in answer once checked (simple first pass)
    }

    @ViewBuilder
    private func indicatorView(isSelected: Bool, reveal: Bool, isCorrect: Bool) -> some View {
        if reveal, isCorrect {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
        } else if reveal, isSelected, !isCorrect {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.red)
        } else if isSelected {
            Image(systemName: "circle.inset.filled")
                .foregroundStyle(AppTheme.forestGreen)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
    }

    private var modalBackground: Color {
        colorScheme == .dark ? Color(white: 0.08) : AppTheme.background
    }

    private var restartSurface: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.7)
    }

    private func scoreLine() -> String {
        let total = questions.count
        let correct = questions.reduce(0) { acc, q in
            let selectedID = selectedAnswerIDByQuestionID[q.id]
            guard let selectedID else { return acc }
            let selected = q.layerItemQuizAnswers.first(where: { $0.id == selectedID })
            return acc + ((selected?.correct ?? false) ? 1 : 0)
        }
        return "Score: \(correct) / \(total)"
    }
}

@MainActor
private enum ChapterImageSelectionMemory {
    static var lastSelectedImageIDByChapterID: [Int: Int] = [:]
}

/// Pinch at fingers’ centroid, pan when zoomed, double-tap to zoom at point / zoom out. SwiftUI’s `MagnificationGesture` only scales about the view center.
private struct ImageZoomGestureOverlay: UIViewRepresentable {
    var imageRect: CGRect
    @Binding var zoomScale: CGFloat
    @Binding var zoomOffset: CGSize
    /// When false (e.g. zoomed in), horizontal swipes pan the image; when true, they change pages.
    var isPagingEnabled: Bool
    var onSingleTap: () -> Void
    var onSwipeToNextPage: () -> Void
    var onSwipeToPreviousPage: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        pinch.cancelsTouchesInView = false

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.maximumNumberOfTouches = 1

        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeLeft))
        swipeLeft.direction = .left
        swipeLeft.delegate = context.coordinator
        swipeLeft.cancelsTouchesInView = false

        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeRight))
        swipeRight.direction = .right
        swipeRight.delegate = context.coordinator
        swipeRight.cancelsTouchesInView = false

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.cancelsTouchesInView = false
        singleTap.require(toFail: doubleTap)

        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(swipeLeft)
        view.addGestureRecognizer(swipeRight)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(singleTap)

        context.coordinator.hostView = view
        context.coordinator.panGR = pan
        context.coordinator.swipeLeftGR = swipeLeft
        context.coordinator.swipeRightGR = swipeRight
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ImageZoomGestureOverlay
        weak var hostView: UIView?
        weak var panGR: UIPanGestureRecognizer?
        weak var swipeLeftGR: UISwipeGestureRecognizer?
        weak var swipeRightGR: UISwipeGestureRecognizer?

        private var pinchBaseScale: CGFloat = 1
        private var pinchLastScale: CGFloat = 1
        private var pinchLastOffset: CGSize = .zero

        private var panStartOffset: CGSize = .zero

        init(_ parent: ImageZoomGestureOverlay) {
            self.parent = parent
        }

        private var center: CGPoint {
            CGPoint(x: parent.imageRect.midX, y: parent.imageRect.midY)
        }

        private var baseSize: CGSize {
            parent.imageRect.size
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let v = g.view else { return }
            let c = center
            switch g.state {
            case .began:
                pinchBaseScale = parent.zoomScale
                pinchLastScale = parent.zoomScale
                pinchLastOffset = parent.zoomOffset
            case .changed:
                let sNew = Self.clampScale(pinchBaseScale * g.scale)
                let focal = g.location(in: v)
                let raw = Self.focalOffset(focal: focal, center: c, oOld: pinchLastOffset, sOld: pinchLastScale, sNew: sNew)
                let oNew = Self.clampPan(raw, scale: sNew, baseSize: baseSize)
                pinchLastScale = sNew
                pinchLastOffset = oNew
                parent.zoomScale = sNew
                parent.zoomOffset = oNew
            case .ended, .cancelled, .failed:
                let sNew = Self.clampScale(pinchBaseScale * g.scale)
                let focal = g.location(in: v)
                let raw = Self.focalOffset(focal: focal, center: c, oOld: pinchLastOffset, sOld: pinchLastScale, sNew: sNew)
                var oNew = Self.clampPan(raw, scale: sNew, baseSize: baseSize)
                if sNew <= 1.001 {
                    oNew = .zero
                }
                parent.zoomScale = sNew
                parent.zoomOffset = oNew
            default:
                break
            }
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard parent.zoomScale > 1.01 else { return }
            switch g.state {
            case .began:
                panStartOffset = parent.zoomOffset
            case .changed:
                let t = g.translation(in: g.view)
                let proposed = CGSize(width: panStartOffset.width + t.x, height: panStartOffset.height + t.y)
                parent.zoomOffset = Self.clampPan(proposed, scale: parent.zoomScale, baseSize: baseSize)
            case .ended, .cancelled, .failed:
                let t = g.translation(in: g.view)
                let proposed = CGSize(width: panStartOffset.width + t.x, height: panStartOffset.height + t.y)
                parent.zoomOffset = Self.clampPan(proposed, scale: parent.zoomScale, baseSize: baseSize)
            default:
                break
            }
        }

        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard let v = g.view else { return }
            let focal = g.location(in: v)
            let c = center
            let bs = baseSize
            if parent.zoomScale > 1.05 {
                parent.zoomScale = 1
                parent.zoomOffset = .zero
            } else {
                let target = CGFloat(2.5)
                let raw = Self.focalOffset(
                    focal: focal,
                    center: c,
                    oOld: parent.zoomOffset,
                    sOld: parent.zoomScale,
                    sNew: target
                )
                parent.zoomScale = target
                parent.zoomOffset = Self.clampPan(raw, scale: target, baseSize: bs)
            }
        }

        @objc func handleSingleTap(_ g: UITapGestureRecognizer) {
            parent.onSingleTap()
        }

        /// RTL-style pages: finger moves right → next page; finger moves left → previous.
        @objc func handleSwipeLeft() {
            guard parent.isPagingEnabled else { return }
            parent.onSwipeToPreviousPage()
        }

        @objc func handleSwipeRight() {
            guard parent.isPagingEnabled else { return }
            parent.onSwipeToNextPage()
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            if g === panGR {
                return parent.zoomScale > 1.01
            }
            if g === swipeLeftGR || g === swipeRightGR {
                return parent.isPagingEnabled
            }
            return true
        }

        func gestureRecognizer(_ g1: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith g2: UIGestureRecognizer) -> Bool {
            if g1 is UIPinchGestureRecognizer && g2 is UIPanGestureRecognizer { return false }
            if g1 is UIPanGestureRecognizer && g2 is UIPinchGestureRecognizer { return false }
            return true
        }

        private static func clampScale(_ s: CGFloat) -> CGFloat {
            min(4, max(1, s))
        }

        private static func clampPan(_ proposed: CGSize, scale: CGFloat, baseSize: CGSize) -> CGSize {
            guard scale > 1.001 else { return .zero }
            let maxX = max(0, ((baseSize.width * scale) - baseSize.width) / 2)
            let maxY = max(0, ((baseSize.height * scale) - baseSize.height) / 2)
            return CGSize(
                width: min(max(proposed.width, -maxX), maxX),
                height: min(max(proposed.height, -maxY), maxY)
            )
        }

        /// Keeps the canvas point under `focal` stable while scale changes (scale about `center`, then `offset`).
        private static func focalOffset(focal: CGPoint, center: CGPoint, oOld: CGSize, sOld: CGFloat, sNew: CGFloat) -> CGSize {
            guard sOld > 0.0001 else { return oOld }
            let ratio = sNew / sOld
            let ox = focal.x - center.x - (focal.x - center.x - oOld.width) * ratio
            let oy = focal.y - center.y - (focal.y - center.y - oOld.height) * ratio
            return CGSize(width: ox, height: oy)
        }
    }
}

private struct ImageChapterReadView: View {
    let chapterId: Int
    let chapterImages: [ChapterImageDTO]
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings

    @State private var selectedImageID: Int?
    @State private var overlaysByImageID: [Int: [ChapterImageOverlayDTO]] = [:]
    @State private var loadingImageIDs: Set<Int> = []
    @State private var errorByImageID: [Int: String] = [:]
    @State private var popup: OverlayPopupState?
    @State private var imageSizeByID: [Int: CGSize] = [:]
    @State private var popupDragStartAnchor: CGPoint?
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero

    private struct OverlayPopupState: Identifiable {
        let id: Int
        let arabic: String
        let translation: String
        var anchor: CGPoint
        var isTranslationExpanded: Bool
    }

    private var sortedImages: [ChapterImageDTO] {
        chapterImages.sorted {
            let lp = $0.position ?? Int.max
            let rp = $1.position ?? Int.max
            if lp != rp { return lp < rp }
            return $0.id < $1.id
        }
    }

    private func goToNextImagePage() {
        guard let id = selectedImageID ?? selectedImage?.id,
              let i = sortedImages.firstIndex(where: { $0.id == id }),
              i + 1 < sortedImages.count else { return }
        selectedImageID = sortedImages[i + 1].id
    }

    private func goToPreviousImagePage() {
        guard let id = selectedImageID ?? selectedImage?.id,
              let i = sortedImages.firstIndex(where: { $0.id == id }),
              i > 0 else { return }
        selectedImageID = sortedImages[i - 1].id
    }

    private var selectedImage: ChapterImageDTO? {
        guard let selectedImageID else { return sortedImages.first }
        return sortedImages.first(where: { $0.id == selectedImageID }) ?? sortedImages.first
    }

    var body: some View {
        Group {
            if sortedImages.isEmpty {
                ContentUnavailableView(
                    "No images",
                    systemImage: "photo.on.rectangle",
                    description: Text("This chapter does not have image pages yet.")
                )
            } else {
                VStack(spacing: 10) {
                    thumbnailsStrip
                    imageViewer
                }
            }
        }
        .onAppear {
            ensureSelection()
        }
        .onChange(of: chapterId) { _, _ in
            popup = nil
            ensureSelection()
        }
        .onChange(of: selectedImageID) { _, newID in
            guard let newID else { return }
            ChapterImageSelectionMemory.lastSelectedImageIDByChapterID[chapterId] = newID
            popup = nil
            zoomScale = 1
            zoomOffset = .zero
            Task {
                await loadOverlaysIfNeeded(for: newID)
                await loadImageSizeIfNeeded(for: newID)
            }
        }
        .task {
            ensureSelection()
            if let id = selectedImage?.id {
                await loadOverlaysIfNeeded(for: id)
                await loadImageSizeIfNeeded(for: id)
            }
        }
    }

    private var thumbnailsStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sortedImages) { page in
                        let isSelected = page.id == selectedImage?.id
                        Button {
                            selectedImageID = page.id
                        } label: {
                            VStack(spacing: 6) {
                                AsyncImage(url: URL(string: page.imageUrl)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    case .failure:
                                        ZStack {
                                            roundedThumbBackground
                                            Image(systemName: "photo")
                                                .foregroundStyle(Color.secondary)
                                        }
                                    default:
                                        ZStack {
                                            roundedThumbBackground
                                            ProgressView()
                                        }
                                    }
                                }
                                .frame(width: 78, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isSelected ? AppTheme.forestGreen : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
                                )

                                Circle()
                                    .fill(Color.white.opacity(isSelected ? 1 : 0))
                                    .frame(width: 8, height: 8)
                                    .shadow(
                                        color: isSelected ? AppTheme.accentBlue.opacity(0.7) : .clear,
                                        radius: isSelected ? 5 : 0,
                                        x: 0,
                                        y: 0
                                    )

                                Text("\((page.position ?? 0) + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(page.id)
                    }
                }
                .padding(.horizontal, 6)
            }
            .onChange(of: selectedImageID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
        .frame(height: 84)
    }

    private var imageViewer: some View {
        let selected = selectedImage
        return ZStack {
            if let selected {
                GeometryReader { geo in
                    let canvas = geo.size
                    let imageSize = imageSizeByID[selected.id] ?? canvas
                    let imageRect = aspectFitRect(content: imageSize, in: CGRect(origin: .zero, size: canvas))
                    let liveScale = clampedScale(zoomScale)
                    let liveOffset = clampedPanOffset(zoomOffset, scale: liveScale, baseSize: imageRect.size)
                    ZStack(alignment: .topLeading) {
                        ImageZoomGestureOverlay(
                            imageRect: imageRect,
                            zoomScale: $zoomScale,
                            zoomOffset: $zoomOffset,
                            isPagingEnabled: clampedScale(zoomScale) <= 1.001 && sortedImages.count > 1,
                            onSingleTap: { popup = nil },
                            onSwipeToNextPage: { goToNextImagePage() },
                            onSwipeToPreviousPage: { goToPreviousImagePage() }
                        )
                        .frame(width: canvas.width, height: canvas.height)
                        .allowsHitTesting(true)

                        ZStack(alignment: .topLeading) {
                            AsyncImage(url: URL(string: selected.imageUrl)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: imageRect.width, height: imageRect.height)
                                case .failure:
                                    ContentUnavailableView("Image failed to load", systemImage: "photo")
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                default:
                                    ProgressView("Loading image…")
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            .allowsHitTesting(false)

                            overlayLayer(
                                for: selected.id,
                                imageRect: CGRect(origin: .zero, size: imageRect.size),
                                hostImageRect: imageRect,
                                scale: liveScale,
                                offset: liveOffset
                            )
                        }
                        .frame(width: imageRect.width, height: imageRect.height, alignment: .topLeading)
                        .scaleEffect(liveScale)
                        .offset(liveOffset)
                        .position(x: imageRect.midX, y: imageRect.midY)

                        // Render popup in viewport coordinates so it keeps a constant size,
                        // independent from image pinch zoom level.
                        if let popup {
                            popupCard(
                                popup,
                                viewportRect: CGRect(origin: .zero, size: canvas)
                            )
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
            } else {
                ContentUnavailableView("No image selected", systemImage: "photo")
            }
        }
        .frame(minHeight: 320, idealHeight: 420)
        .background(colorScheme == .dark ? Color(white: 0.10) : Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func overlayLayer(
        for imageID: Int,
        imageRect: CGRect,
        hostImageRect: CGRect,
        scale: CGFloat,
        offset: CGSize
    ) -> some View {
        if loadingImageIDs.contains(imageID) {
            VStack {
                Spacer()
                ProgressView("Loading overlays…")
                    .font(.caption)
                    .padding(8)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(Color.white)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = errorByImageID[imageID] {
            VStack {
                Spacer()
                Text(message)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .background(Color.black.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(Color.white)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let overlays = overlaysByImageID[imageID] ?? []
            ForEach(overlays) { overlay in
                overlayShapeView(
                    overlay,
                    imageRect: imageRect,
                    hostImageRect: hostImageRect,
                    scale: scale,
                    offset: offset
                )
            }
        }
    }

    @ViewBuilder
    private func overlayShapeView(
        _ overlay: ChapterImageOverlayDTO,
        imageRect: CGRect,
        hostImageRect: CGRect,
        scale: CGFloat,
        offset: CGSize
    ) -> some View {
        let kind = (overlay.overlayType ?? "rect").lowercased()
        if kind == "polygon", let points = polygonPoints(from: overlay.shape, imageRect: imageRect), points.count >= 3 {
            Path { p in
                p.move(to: points[0])
                for pt in points.dropFirst() { p.addLine(to: pt) }
                p.closeSubpath()
            }
            .stroke(overlayStrokeColor, lineWidth: 1.6)
            .background(
                Path { p in
                    p.move(to: points[0])
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                    p.closeSubpath()
                }
                .fill(overlayFillColor)
            )
            .contentShape(
                Path { p in
                    p.move(to: points[0])
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                    p.closeSubpath()
                }
            )
            .onTapGesture {
                let center = polygonCenter(points)
                showPopup(
                    for: overlay,
                    anchor: transformedToViewport(point: center, hostImageRect: hostImageRect, scale: scale, offset: offset)
                )
            }
        } else if let rect = overlayRect(from: overlay.shape, imageRect: imageRect) {
            overlayRectView(kind: kind, rect: rect)
                .onTapGesture {
                    showPopup(
                        for: overlay,
                        anchor: transformedToViewport(
                            point: CGPoint(x: rect.midX, y: rect.midY),
                            hostImageRect: hostImageRect,
                            scale: scale,
                            offset: offset
                        )
                    )
                }
        }
    }

    @ViewBuilder
    private func overlayRectView(kind: String, rect: CGRect) -> some View {
        if kind == "ellipse" {
            Ellipse()
                .fill(overlayFillColor)
                .overlay(Ellipse().stroke(overlayStrokeColor, lineWidth: 1.6))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        } else if kind == "rounded-rect" {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(overlayFillColor)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(overlayStrokeColor, lineWidth: 1.6))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        } else {
            Rectangle()
                .fill(overlayFillColor)
                .overlay(Rectangle().stroke(overlayStrokeColor, lineWidth: 1.6))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    private func popupCard(_ popup: OverlayPopupState, viewportRect: CGRect) -> some View {
        let cardW = min(viewportRect.width - 20, 320.0)
        let popupFontSize = max(20, min(appSettings.contentFontSize, 44))
        let cardH: CGFloat = popup.isTranslationExpanded ? 210 : 142
        let minX = viewportRect.minX + cardW / 2 + 10
        let maxX = viewportRect.maxX - cardW / 2 - 10
        let minY = viewportRect.minY + cardH / 2 + 10
        let maxY = viewportRect.maxY - cardH / 2 - 10
        let x = min(max(popup.anchor.x, minX), maxX)

        // Try to keep the card away from the tapped bubble by preferring
        // either clearly above or clearly below its anchor point.
        let bubbleClearance: CGFloat = 52
        let preferredAboveY = popup.anchor.y - (cardH / 2 + bubbleClearance)
        let preferredBelowY = popup.anchor.y + (cardH / 2 + bubbleClearance)
        let aboveFits = preferredAboveY >= minY
        let belowFits = preferredBelowY <= maxY
        let y: CGFloat
        if aboveFits {
            y = preferredAboveY
        } else if belowFits {
            y = preferredBelowY
        } else {
            // If both directions are constrained, pick the side with more room.
            let roomAbove = popup.anchor.y - minY
            let roomBelow = maxY - popup.anchor.y
            let fallback = roomAbove >= roomBelow ? preferredAboveY : preferredBelowY
            y = min(max(fallback, minY), maxY)
        }

        return VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    self.popup = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
                Button {
                    guard var currentPopup = self.popup else { return }
                    currentPopup.isTranslationExpanded.toggle()
                    self.popup = currentPopup
                } label: {
                    Text(popup.isTranslationExpanded ? "Tap to Hide Translation" : "Tap to Translate")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.55))
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                if let label = overlaysByImageID[selectedImage?.id ?? -1]?.first(where: { $0.id == popup.id })?.label, !label.isEmpty {
                    Text("#\(label)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                }
            }

            Text(popup.arabic)
                .font(ArabicTypography.swiftUIFont(size: popupFontSize))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard var currentPopup = self.popup else { return }
                    currentPopup.isTranslationExpanded.toggle()
                    self.popup = currentPopup
                }

            if popup.isTranslationExpanded {
                Text(popup.translation)
                    .font(.system(size: max(14, popupFontSize * 0.72)))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(width: cardW, alignment: .topLeading)
        .background(.regularMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
        .position(x: x, y: y)
        .onTapGesture { }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    guard var currentPopup = self.popup else { return }
                    if popupDragStartAnchor == nil {
                        popupDragStartAnchor = currentPopup.anchor
                    }
                    let start = popupDragStartAnchor ?? currentPopup.anchor
                    currentPopup.anchor = CGPoint(
                        x: start.x + value.translation.width,
                        y: start.y + value.translation.height
                    )
                    self.popup = currentPopup
                }
                .onEnded { _ in
                    popupDragStartAnchor = nil
                }
        )
    }

    private func ensureSelection() {
        guard !sortedImages.isEmpty else {
            selectedImageID = nil
            return
        }
        if let persisted = ChapterImageSelectionMemory.lastSelectedImageIDByChapterID[chapterId],
           sortedImages.contains(where: { $0.id == persisted }) {
            selectedImageID = persisted
            return
        }
        if let selectedImageID, sortedImages.contains(where: { $0.id == selectedImageID }) {
            return
        }
        selectedImageID = sortedImages[0].id
    }

    private func loadOverlaysIfNeeded(for imageID: Int) async {
        if overlaysByImageID[imageID] != nil { return }
        if loadingImageIDs.contains(imageID) { return }
        loadingImageIDs.insert(imageID)
        errorByImageID[imageID] = nil
        defer { loadingImageIDs.remove(imageID) }
        do {
            let overlays = try await ChapterAPI.fetchChapterImageOverlays(chapterImageId: imageID)
            overlaysByImageID[imageID] = overlays
        } catch {
            overlaysByImageID[imageID] = []
            errorByImageID[imageID] = error.localizedDescription
        }
    }

    private func overlayRect(from shape: [String: JSONValue]?, imageRect: CGRect) -> CGRect? {
        guard let shape else { return nil }
        guard
            let x = percentNumber(shape["x"]),
            let y = percentNumber(shape["y"]),
            let width = percentNumber(shape["width"]),
            let height = percentNumber(shape["height"])
        else { return nil }

        let px = imageRect.minX + (x / 100) * imageRect.width
        let py = imageRect.minY + (y / 100) * imageRect.height
        let pw = (width / 100) * imageRect.width
        let ph = (height / 100) * imageRect.height
        return CGRect(x: px, y: py, width: pw, height: ph)
    }

    private func polygonPoints(from shape: [String: JSONValue]?, imageRect: CGRect) -> [CGPoint]? {
        guard let shape, let pointsValue = shape["points"], case .array(let pointsArray) = pointsValue else { return nil }
        var points: [CGPoint] = []
        for v in pointsArray {
            guard case .object(let dict) = v,
                  let x = percentNumber(dict["x"]),
                  let y = percentNumber(dict["y"]) else { continue }
            points.append(
                CGPoint(
                    x: imageRect.minX + (x / 100) * imageRect.width,
                    y: imageRect.minY + (y / 100) * imageRect.height
                )
            )
        }
        return points.isEmpty ? nil : points
    }

    private func polygonCenter(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        let sx = pts.reduce(0) { $0 + $1.x }
        let sy = pts.reduce(0) { $0 + $1.y }
        return CGPoint(x: sx / CGFloat(pts.count), y: sy / CGFloat(pts.count))
    }

    private func percentNumber(_ value: JSONValue?) -> CGFloat? {
        switch value {
        case .number(let d):
            return CGFloat(d)
        case .string(let s):
            return CGFloat(Double(s) ?? .nan).isFinite ? CGFloat(Double(s) ?? 0) : nil
        default:
            return nil
        }
    }

    private func showPopup(for overlay: ChapterImageOverlayDTO, anchor: CGPoint) {
        let arabic = nonEmpty(overlay.original) ?? "لا يوجد نص عربي."
        let translation = nonEmpty(overlay.translation) ?? "No translation available."
        popup = OverlayPopupState(
            id: overlay.id,
            arabic: arabic,
            translation: translation,
            anchor: anchor,
            isTranslationExpanded: false
        )
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private var roundedThumbBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.7))
    }

    private var overlayStrokeColor: Color {
        colorScheme == .dark ? Color.yellow.opacity(0.85) : Color.orange.opacity(0.85)
    }

    private var overlayFillColor: Color {
        colorScheme == .dark ? Color.yellow.opacity(0.16) : Color.orange.opacity(0.14)
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(4, max(1, scale))
    }

    private func clampedPanOffset(_ proposed: CGSize, scale: CGFloat, baseSize: CGSize) -> CGSize {
        guard scale > 1.001 else { return .zero }
        let maxX = max(0, ((baseSize.width * scale) - baseSize.width) / 2)
        let maxY = max(0, ((baseSize.height * scale) - baseSize.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func transformedToViewport(point: CGPoint, hostImageRect: CGRect, scale: CGFloat, offset: CGSize) -> CGPoint {
        // Convert from local image-space point (unscaled) to current viewport point
        // after scale-about-center + pan translation.
        let x0 = hostImageRect.minX + point.x
        let y0 = hostImageRect.minY + point.y
        let cx = hostImageRect.midX
        let cy = hostImageRect.midY
        return CGPoint(
            x: cx + (x0 - cx) * scale + offset.width,
            y: cy + (y0 - cy) * scale + offset.height
        )
    }

    private func aspectFitRect(content: CGSize, in bounds: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let w = content.width * scale
        let h = content.height * scale
        let x = bounds.minX + (bounds.width - w) / 2
        let y = bounds.minY + (bounds.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func loadImageSizeIfNeeded(for imageID: Int) async {
        if imageSizeByID[imageID] != nil { return }
        guard let image = sortedImages.first(where: { $0.id == imageID }),
              let url = URL(string: image.imageUrl) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            #if canImport(UIKit)
            if let ui = UIImage(data: data), ui.size.width > 0, ui.size.height > 0 {
                imageSizeByID[imageID] = ui.size
            }
            #endif
        } catch {
            // Best effort only; overlay mapping falls back to container size.
        }
    }
}

private struct WaveformSeeker: View {
    let samples: [Float]
    let progress: Double
    let onSeek: (Double) -> Void

    @GestureState private var isDragging = false
    @State private var dragX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let p = max(0, min(1, isDragging ? (Double((dragX ?? 0) / w)) : progress))
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.55))

                Canvas { context, size in
                    let midY = size.height / 2
                    let barCount = max(24, Int(size.width / 4))
                    let amps = downsample(samples, to: barCount)
                    let barW = size.width / CGFloat(barCount)

                    for i in 0..<barCount {
                        let amp = CGFloat(amps[i])
                        let h = max(2, amp * (size.height - 8))
                        let x = CGFloat(i) * barW + (barW * 0.5)
                        let rect = CGRect(x: x - 1.2, y: midY - h / 2, width: 2.4, height: h)
                        let color: Color = (Double(i) / Double(barCount)) <= p ? AppTheme.forestGreen : AppTheme.textSecondary.opacity(0.35)
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                    }

                    // playhead
                    let playX = CGFloat(p) * size.width
                    var path = Path()
                    path.addRoundedRect(in: CGRect(x: playX - 1, y: 4, width: 2, height: size.height - 8), cornerSize: CGSize(width: 1, height: 1))
                    context.fill(path, with: .color(AppTheme.forestGreen.opacity(0.85)))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, s, _ in s = true }
                    .onChanged { v in
                        dragX = max(0, min(v.location.x, w))
                    }
                    .onEnded { v in
                        let pct = max(0, min(1, Double(v.location.x / w)))
                        dragX = nil
                        onSeek(pct)
                    }
            )
        }
    }

    private func downsample(_ input: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !input.isEmpty else { return Array(repeating: 0.15, count: count) }
        if input.count <= count { return input + Array(repeating: input.last ?? 0, count: count - input.count) }
        let stride = Double(input.count) / Double(count)
        return (0 ..< count).map { i in
            let start = Int(Double(i) * stride)
            let end = min(input.count, Int(Double(i + 1) * stride))
            return input[start..<end].max() ?? 0
        }
    }
}

private struct LiveWaveformRow: View {
    let samples: [Float]

    var body: some View {
        WaveformSeeker(samples: samples, progress: 1, onSeek: { _ in })
            .frame(height: 44)
            .overlay(alignment: .leading) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Recording…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.leading, 12)
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Layer rendering (read-only, default layer)

private enum LayerItemGroup: Identifiable {
    case inline([ChapterLayerItem])
    case single(ChapterLayerItem)

    var id: String {
        switch self {
        case .inline(let items):
            return "i-" + items.map { String($0.id) }.joined(separator: "-")
        case .single(let item):
            return "s-\(item.id)"
        }
    }
}

private func groupedItems(_ items: [ChapterLayerItem]) -> [LayerItemGroup] {
    let sorted = items.sorted { $0.position < $1.position }
    var groups: [LayerItemGroup] = []
    var run: [ChapterLayerItem] = []
    for item in sorted {
        if item.style == "inline" {
            run.append(item)
        } else {
            if !run.isEmpty {
                groups.append(.inline(run))
                run = []
            }
            groups.append(.single(item))
        }
    }
    if !run.isEmpty {
        groups.append(.inline(run))
    }
    return groups
}

struct DefaultLayerContentView: View {
    let items: [ChapterLayerItem]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groupedItems(items)) { group in
                switch group {
                case .inline(let parts):
                    InlineLayerRow(items: parts)
                case .single(let item):
                    LayerSingleItemView(item: item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(ArabicTypography.swiftUIFont(size: UIFont.preferredFont(forTextStyle: .title2).pointSize))
        .lineSpacing(10)
        .foregroundStyle(colorScheme == .dark ? Color.white : AppTheme.textPrimary)
    }
}

private struct InlineLayerRow: View {
    let items: [ChapterLayerItem]

    var body: some View {
        InlineFlowLayout(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                HintToggleItem(hint: item.hint, mode: .inline) {
                    InlineSegmentText(html: item.body, addTrailingSpace: idx != items.count - 1)
                }
            }
        }
        .padding(.vertical, 0)
    }
}

private struct LayerSingleItemView: View {
    let item: ChapterLayerItem
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HintToggleItem(hint: item.hint, mode: .block) {
            Group {
                switch item.style {
                case "header":
                    ItemBodyText(html: item.body)
                        .font(ArabicTypography.swiftUIFont(size: UIFont.preferredFont(forTextStyle: .title2).pointSize).weight(.semibold))
                case "block":
                    ItemBodyText(html: item.body)
                        .padding(.vertical, 6)
                case "quote":
                    ItemBodyText(html: item.body)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(quoteBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case "bullet":
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        ItemBodyText(html: item.body)
                    }
                    .padding(.vertical, 2)
                case "ordered":
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("◦")
                            .foregroundStyle(Color.secondary)
                        ItemBodyText(html: item.body)
                    }
                    .padding(.vertical, 2)
                case "line_break":
                    Color.clear.frame(height: 12)
                case "hr":
                    Divider().padding(.vertical, 12)
                case "inline":
                    ItemBodyText(html: item.body)
                default:
                    ItemBodyText(html: item.body)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private var quoteBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : AppTheme.searchFieldGray.opacity(0.85)
    }
}

// MARK: - Hint toggle (Genius-style)

private struct DashedUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.midY
        p.move(to: CGPoint(x: rect.minX, y: y))
        p.addLine(to: CGPoint(x: rect.maxX, y: y))
        return p
    }
}

private struct HintToggleItem<Content: View>: View {
    enum Mode {
        case inline
        case block
    }

    let hint: String?
    let mode: Mode
    @ViewBuilder let content: () -> Content

    @State private var showHint = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: mode == .inline ? 2 : 8) {
            content()
                .frame(maxWidth: mode == .block ? .infinity : nil, alignment: .leading)
                .padding(hasHint ? (mode == .block ? 10 : 2) : 0)
                .background {
                    if hasHint, showHint {
                        RoundedRectangle(cornerRadius: mode == .block ? 8 : 4, style: .continuous)
                            .fill(hintActiveHighlightBackground)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if hasHint, !showHint {
                        DashedUnderline()
                            .stroke(
                                hintUnderlineColor,
                                style: StrokeStyle(lineWidth: underlineLineWidth, lineCap: .round, dash: [3, 6])
                            )
                            .frame(height: 6)
                            .padding(.horizontal, mode == .block ? 10 : 2)
                            .offset(y: mode == .block ? 8 : 4)
                            .shadow(color: hintUnderlineColor.opacity(colorScheme == .dark ? 0.08 : 0.22), radius: 0.4, x: 0, y: 0.4)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard hasHint else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showHint.toggle()
                    }
                }

            if showHint, let normalizedHint {
                Text(normalizedHint)
                    .font(.body)
                    .foregroundStyle(hintTextColor)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(hintExpandedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
    }

    private var normalizedHint: String? {
        guard let trimmed = hint?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private var hasHint: Bool {
        normalizedHint != nil
    }

    private var hintExpandedBackground: Color {
        colorScheme == .dark ? Color(hex: 0x5D4E1E, alpha: 0.36) : AppTheme.hintExpandedFill
    }

    private var hintTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.secondary
    }

    private var hintUnderlineColor: Color {
        colorScheme == .dark ? Color(hex: 0xD7C075, alpha: 0.52) : AppTheme.hintUnderline
    }

    private var underlineLineWidth: CGFloat {
        colorScheme == .dark ? 1.8 : 2.5
    }

    private var hintActiveHighlightBackground: Color {
        // In dark mode, use a deeper warm tint so white Arabic text remains legible.
        colorScheme == .dark ? Color(hex: 0x6A5A1F, alpha: 0.48) : AppTheme.hintHighlight
    }
}

private struct InlineSegmentText: View {
    let html: String
    let addTrailingSpace: Bool
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        let attributed = ItemBodyText.attributed(from: html, fontSize: appSettings.contentFontSize)
        Text(attributedWithOptionalSpace(attributed))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func attributedWithOptionalSpace(_ base: AttributedString) -> AttributedString {
        guard addTrailingSpace else { return base }
        // Only add a space if the segment doesn't already end in whitespace.
        if let last = base.characters.last, last.isWhitespace { return base }
        var copy = base
        copy.append(AttributedString(" "))
        return copy
    }
}

private struct InlineFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    private func maxLineWidth(from proposal: ProposedViewSize) -> CGFloat {
        if let w = proposal.width, w.isFinite, w > 0 { return w }
        return 320
    }

    /// Avoid placing the next item in a narrow “sliver” at the end of a row (causes one-word columns).
    private func minimumRemainderToShareLine(maxLine: CGFloat) -> CGFloat {
        // Keep this small; measuring items with constrained widths can otherwise cause
        // premature line breaks that feel unlike paragraph wrapping.
        max(12, min(48, maxLine * 0.10))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxLine = max(1, maxLineWidth(from: proposal))
        let minRemainder = minimumRemainderToShareLine(maxLine: maxLine)
        var lineX: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestLine: CGFloat = 0

        for subview in subviews {
            if lineX > 0 {
                let spacing = horizontalSpacing
                let sliver = maxLine - lineX - spacing
                if sliver < minRemainder {
                    totalHeight += lineHeight + verticalSpacing
                    widestLine = max(widestLine, min(lineX, maxLine))
                    lineX = 0
                    lineHeight = 0
                }
            }

            let spacing = lineX > 0 ? horizontalSpacing : 0
            var remaining = maxLine - lineX - spacing
            if remaining < 1 {
                totalHeight += lineHeight + verticalSpacing
                widestLine = max(widestLine, min(lineX, maxLine))
                lineX = 0
                lineHeight = 0
                remaining = maxLine
            }

            // Measure with an unconstrained proposal first. If we measure with `remaining`,
            // SwiftUI may wrap the subview during measurement, report it as "full width",
            // and force the *next* item onto a new line (paragraph-breaking behavior).
            let ideal = subview.sizeThatFits(.unspecified)
            var proposeW = ideal.width
            var size = ideal

            // If it doesn't fit on the current line, wrap before placing it.
            if lineX > 0, ideal.width > remaining + 0.5 {
                totalHeight += lineHeight + verticalSpacing
                widestLine = max(widestLine, min(lineX, maxLine))
                lineX = 0
                lineHeight = 0
                remaining = maxLine
            }

            // Now constrain only if the item is wider than the line (allow internal wrapping).
            if ideal.width > maxLine {
                proposeW = maxLine
                size = subview.sizeThatFits(ProposedViewSize(width: proposeW, height: nil))
            } else {
                // Propose the ideal width so the view doesn't expand to `remaining`.
                proposeW = ideal.width
                size = ideal
            }

            lineX += spacing + size.width
            lineHeight = max(lineHeight, size.height)
        }

        widestLine = max(widestLine, min(lineX, maxLine))
        totalHeight += lineHeight
        return CGSize(width: min(widestLine, maxLine), height: max(totalHeight, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxLine = bounds.width
        let minRemainder = minimumRemainderToShareLine(maxLine: maxLine)
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            if x > bounds.minX + 0.5 {
                let spacing = horizontalSpacing
                let sliver = bounds.maxX - x - spacing
                if sliver < minRemainder {
                    x = bounds.minX
                    y += rowHeight + verticalSpacing
                    rowHeight = 0
                }
            }

            let spacing = x > bounds.minX + 0.5 ? horizontalSpacing : 0
            var remaining = bounds.maxX - x - spacing
            if remaining < 1 {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
                remaining = bounds.maxX - bounds.minX
            }

            let ideal = subview.sizeThatFits(.unspecified)
            var proposeW = ideal.width
            var size = ideal

            if x > bounds.minX + 0.5, ideal.width > remaining + 0.5 {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
                remaining = bounds.maxX - bounds.minX
            }

            if ideal.width > maxLine {
                proposeW = maxLine
                size = subview.sizeThatFits(ProposedViewSize(width: proposeW, height: nil))
            } else {
                proposeW = ideal.width
                size = ideal
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: proposeW, height: nil)
            )
            x += spacing + size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - HTML → AttributedString

struct ItemBodyText: View {
    let html: String
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        Text(Self.attributed(from: html, fontSize: appSettings.contentFontSize))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func attributed(from html: String, fontSize: CGFloat = 30) -> AttributedString {
        guard let data = html.data(using: .utf8) else { return AttributedString(html) }
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let ns = try? NSAttributedString(data: data, options: opts, documentAttributes: nil) {
            let mutable = NSMutableAttributedString(attributedString: ns)
            let full = NSRange(location: 0, length: mutable.length)

            let baseUIFont = ArabicTypography.uiFont(size: fontSize)
            mutable.enumerateAttribute(.font, in: full) { value, range, _ in
                let current = (value as? UIFont) ?? baseUIFont
                let traits = current.fontDescriptor.symbolicTraits
                let descriptor = baseUIFont.fontDescriptor.withSymbolicTraits(traits) ?? baseUIFont.fontDescriptor
                let resized = UIFont(descriptor: descriptor, size: fontSize)
                mutable.addAttribute(.font, value: resized, range: range)
            }
            mutable.addAttribute(.foregroundColor, value: UIColor.label, range: full)

            return AttributedString(mutable)
        }
        return AttributedString(html)
    }
}
