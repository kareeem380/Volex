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
            // Header - Pro Style
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.mode == .clipboard ? "doc.on.clipboard" : "app.grid.3x3")
                        .font(.system(size: 12, weight: .black))
                    Text(viewModel.mode == .clipboard ? "Clipboard" : "Applications")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(1.2)
                }
                .foregroundColor(.secondary)
                
                Spacer()
                
                Text(viewModel.mode == .clipboard ? "Tab to Apps" : "Tab to Clipboard")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 30)
            .padding(.top, 25)
            
            // Search Bar - Modern Pill Style
            HStack(spacing: 15) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.accentColor)
                
                TextField(viewModel.mode == .clipboard ? "Search history..." : "Search apps...", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        viewModel.launchSelected(onComplete: onActionComplete)
                    }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule() // The ultimate Apple rounding
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal, 25)
            .padding(.vertical, 20)
            
            // Results with Liquid feel
            if viewModel.results.isEmpty {
                VStack(spacing: 25) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.accentColor.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: viewModel.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                            .font(.system(size: 60, weight: .thin))
                            .foregroundStyle(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                    }
                    
                    VStack(spacing: 8) {
                        Text(viewModel.query.isEmpty ? "Clipboard is Empty" : "No Matches Found")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary.opacity(0.8))
                        
                        Text(viewModel.query.isEmpty ? "Copy something and it will appear here." : "Try a different search term.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(0.98)))
            } else {
                ScrollViewReader { proxy in
                    List(Array(viewModel.results.enumerated()), id: \.element.hashValue) { index, item in
                        ResultRow(item: item, isSelected: viewModel.selectedIndex == index, mode: viewModel.mode)
                            .id(index)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)) // Increased spacing
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden) // Cleaner look
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.selectedIndex = index
                                }
                                viewModel.launchSelected(onComplete: onActionComplete)
                            }
                    }
                    .listStyle(.plain)
                    .padding(.top, 10)
                    .onChange(of: viewModel.selectedIndex) { oldValue, newValue in
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.1)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(VisualEffectView(material: .fullScreenUI).ignoresSafeArea())
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

struct ResultRow: View {
    let item: AnyHashable
    let isSelected: Bool
    let mode: SearchMode
    
    var body: some View {
        HStack(spacing: 16) {
            if mode == .apps, let app = item as? AppResult {
                Image(nsImage: app.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    if isSelected {
                        Text(app.path)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
            } else if mode == .clipboard, let clip = item as? ClipboardItem {
                VStack(alignment: .leading, spacing: 8) {
                    Text(clip.text)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(isSelected ? .white : .primary.opacity(0.9))
                        .lineLimit(isSelected ? 4 : 1) // Intelligent truncation
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: isSelected)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                        Text("\(RelativeDateTimeFormatter().localizedString(for: clip.timestamp, relativeTo: Date()))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                        
                        Spacer()
                        
                        if isSelected {
                            HStack(spacing: 4) {
                                Text("PASTE")
                                Image(systemName: "arrow.right.doc.on.clipboard")
                            }
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.6))
                }
            }
            
            if mode == .apps && isSelected {
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.vertical, 8) // Balanced density
        .padding(.horizontal, 16)
        .background(
            ZStack {
                if isSelected {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.85), Color.accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color.primary.opacity(0.05)
                }
            }
            .cornerRadius(20) // Apply to the whole container
            .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isSelected ? Color.white.opacity(0.2) : Color.clear, lineWidth: 0.5)
        )
        .scaleEffect(isSelected ? 1.015 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
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
