import SwiftUI
import AppKit
import Combine

enum SearchMode {
    case apps
    case clipboard
}

struct AppResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let icon: NSImage
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

class SearchViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet {
            filterResults()
        }
    }
    @Published var mode: SearchMode = .clipboard {
        didSet {
            filterResults()
        }
    }
    @Published var results: [AnyHashable] = []
    @Published var selectedIndex: Int = 0
    
    private var allApps: [AppResult] = []
    private let metadataQuery = NSMetadataQuery()
    private let clipboardManager = ClipboardManager()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupMetadataQuery()
        
        // Listen to clipboard changes
        clipboardManager.$history
            .sink { [weak self] _ in
                if self?.mode == .clipboard {
                    self?.filterResults()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupMetadataQuery() {
        metadataQuery.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        metadataQuery.searchScopes = ["/Applications", "/System/Applications"]
        
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: metadataQuery, queue: .main) { [weak self] _ in
            self?.processQueryResults()
        }
        
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: metadataQuery, queue: .main) { [weak self] _ in
            self?.processQueryResults()
        }
        
        metadataQuery.start()
    }
    
    private func processQueryResults() {
        var apps: [AppResult] = []
        for i in 0..<metadataQuery.resultCount {
            if let item = metadataQuery.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: kMDItemPath as String) as? String,
               let name = item.value(forAttribute: kMDItemDisplayName as String) as? String {
                let icon = NSWorkspace.shared.icon(forFile: path)
                apps.append(AppResult(name: name, path: path, icon: icon))
            }
        }
        self.allApps = apps.sorted { $0.name < $1.name }
        filterResults()
    }
    
    func filterResults() {
        switch mode {
        case .apps:
            if query.isEmpty {
                results = Array(allApps.prefix(10))
            } else {
                let lowerQuery = query.lowercased()
                results = allApps.compactMap { app -> (AppResult, Int)? in
                    let score = calculateScore(query: lowerQuery, target: app.name.lowercased())
                    return score > 0 ? (app, score) : nil
                }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
            }
        case .clipboard:
            if query.isEmpty {
                results = clipboardManager.history
            } else {
                let lowerQuery = query.lowercased()
                results = clipboardManager.history.compactMap { item -> (ClipboardItem, Int)? in
                    let score = calculateScore(query: lowerQuery, target: item.text.lowercased())
                    return score > 0 ? (item, score) : nil
                }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
            }
        }
        selectedIndex = 0
    }
    
    private func calculateScore(query: String, target: String) -> Int {
        if target == query { return 1000 }
        if target.hasPrefix(query) { return 900 }
        
        var score = 0
        let words = target.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        
        for word in words {
            if word.hasPrefix(query) {
                score = max(score, 500)
            }
        }
        
        let initials = words.compactMap { $0.first }.map { String($0) }.joined().lowercased()
        if initials.hasPrefix(query) {
            score = max(score, 400 + query.count * 10)
        }
        
        if score == 0 {
            var targetIdx = target.startIndex
            var matchCount = 0
            for char in query {
                if let range = target.range(of: String(char), options: .caseInsensitive, range: targetIdx..<target.endIndex) {
                    matchCount += 1
                    targetIdx = range.upperBound
                } else {
                    return 0
                }
            }
            score = 100 + matchCount
        }
        
        return score
    }
    
    func selectNext() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % results.count
    }
    
    func selectPrevious() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + results.count) % results.count
    }
    
    func launchSelected(onComplete: @escaping () -> Void, showInFinder: Bool = false) {
        guard selectedIndex < results.count else { return }
        
        if mode == .apps, let app = results[selectedIndex] as? AppResult {
            let url = URL(fileURLWithPath: app.path)
            if showInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url)
            }
            onComplete()
        } else if mode == .clipboard, let item = results[selectedIndex] as? ClipboardItem {
            // 1. Hide the window first to let the target app get focus
            onComplete()
            
            // 2. Update pasteboard
            clipboardManager.copyToPasteboard(item)
            
            // 3. Simulate paste
            clipboardManager.simulatePaste()
        }
    }
    
    func toggleMode() {
        mode = (mode == .apps) ? .clipboard : .apps
        query = ""
    }
}

struct ContentView: View {
    @StateObject private var viewModel = SearchViewModel()
    @FocusState private var isSearchFieldFocused: Bool
    var onActionComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar - Spotlight Style (at the very top)
            HStack(spacing: 15) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .thin))
                    .foregroundColor(.primary.opacity(0.6))
                
                TextField(viewModel.mode == .clipboard ? "Search history..." : "Search apps...", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .light)) // Spotlight size
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        viewModel.launchSelected(onComplete: onActionComplete)
                    }
                
                if !viewModel.query.isEmpty {
                    Button(action: { viewModel.query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 22)
            
            Divider()
                .opacity(0.1)
            
            // Suggestion Chips (Quick Actions)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    SuggestionChip(title: "Clipboard", icon: "doc.on.clipboard", isSelected: viewModel.mode == .clipboard) {
                        viewModel.mode = .clipboard
                    }
                    SuggestionChip(title: "Applications", icon: "app.grid.3x3", isSelected: viewModel.mode == .apps) {
                        viewModel.mode = .apps
                    }
                    SuggestionChip(title: "Files", icon: "folder", isSelected: false) { }
                    SuggestionChip(title: "Settings", icon: "gearshape", isSelected: false) { }
                }
                .padding(.horizontal, 25)
            }
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.02))
            
            Divider()
                .opacity(0.1)
            
            // Results with High Density
            if viewModel.results.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: viewModel.mode == .clipboard ? "doc.on.clipboard" : "app.grid.3x3")
                        .font(.system(size: 44, weight: .ultraLight))
                        .foregroundColor(.secondary.opacity(0.3))
                    
                    Text(viewModel.query.isEmpty ? (viewModel.mode == .clipboard ? "Clipboard is Empty" : "No Apps Found") : "No Matches Found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    List(Array(viewModel.results.enumerated()), id: \.element.hashValue) { index, item in
                        ResultRow(item: item, isSelected: viewModel.selectedIndex == index, mode: viewModel.mode)
                            .id(index)
                            .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                    viewModel.selectedIndex = index
                                }
                                viewModel.launchSelected(onComplete: onActionComplete)
                            }
                    }
                    .listStyle(.plain)
                    .padding(.top, 8)
                    .onChange(of: viewModel.selectedIndex) { oldValue, newValue in
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        .onAppear {
            isSearchFieldFocused = true
        }
        .background(
            KeyEventHandlingView { event in
                if event.keyCode == 48 { // Tab
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.toggleMode()
                    }
                    return true
                }
                if event.keyCode == 53 { // Esc
                    onActionComplete()
                    return true
                }
                if event.keyCode == 125 { // Down
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                        viewModel.selectNext()
                    }
                    return true
                } else if event.keyCode == 126 { // Up
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                        viewModel.selectPrevious()
                    }
                    return true
                }
                return false
            }
        )
    }
}

struct SuggestionChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
            )
            .foregroundColor(isSelected ? .white : .primary.opacity(0.8))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isSelected ? 0.2 : 0.05), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ResultRow: View {
    let item: AnyHashable
    let isSelected: Bool
    let mode: SearchMode
    
    var body: some View {
        HStack(spacing: 12) {
            if mode == .apps, let app = item as? AppResult {
                Image(nsImage: app.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .padding(4)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    if isSelected {
                        Text(app.path)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            } else if mode == .clipboard, let clip = item as? ClipboardItem {
                VStack(alignment: .leading, spacing: 6) {
                    Text(clip.text)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(isSelected ? .white : .primary.opacity(0.9))
                        .lineLimit(isSelected ? 5 : 1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack(spacing: 6) {
                        Text("\(RelativeDateTimeFormatter().localizedString(for: clip.timestamp, relativeTo: Date()))")
                            .font(.system(size: 10, weight: .medium))
                        
                        Spacer()
                        
                        if isSelected {
                            Text("PASTE")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundColor(isSelected ? .white.opacity(0.6) : .secondary.opacity(0.5))
                }
            }
            
            if mode == .apps && isSelected {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            ZStack {
                if isSelected {
                    Color.accentColor
                        .opacity(0.95)
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) // Matching native Spotlight item shape
        .padding(.horizontal, 4)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = blendingMode
        view.state = .active
        view.material = material
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// Helper for Global Keyboard Events within the view
struct KeyEventHandlingView: NSViewRepresentable {
    let onKeyEvent: (NSEvent) -> Bool
    
    class KeyView: NSView {
        var onKeyEvent: ((NSEvent) -> Bool)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if onKeyEvent?(event) == false {
                super.keyDown(with: event)
            }
        }
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onKeyEvent = onKeyEvent
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
