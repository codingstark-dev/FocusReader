import SwiftUI
import AppKit

// MARK: - Toolbar View
/// Capsule floating pill that attaches seamlessly near the bottom center of the Books reading window.
struct ToolbarView: View {
    @ObservedObject var engine: RSVPEngine
    let onFocusRead: () -> Void
    let onClose:     () -> Void

    var body: some View {
        let theme = engine.selectedTheme
        
        ZStack {
            // Elegant background pill (semi-translucent frosted glass backing)
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                
            HStack(spacing: 0) {
                // Book Symbol & Title
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(theme.accentColor)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(engine.bookTitle)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                        if !engine.bookAuthor.isEmpty {
                            Text(engine.bookAuthor)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(width: 180, alignment: .leading)
                .padding(.leading, 18)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                
                // Focus Read Button
                Button(action: onFocusRead) {
                    HStack(spacing: 6) {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(engine.isPlaying ? "Pause" : "Focus Read")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(engine.isPlaying ? Color.white.opacity(0.15) : theme.accentColor)
                    )
                    .shadow(color: engine.isPlaying ? .clear : theme.accentColor.opacity(0.35), radius: 6)
                }
                .buttonStyle(.plain)
                .help("Launch the speed reading overlay")
                
                Spacer()
                
                // Speed controls
                HStack(spacing: 6) {
                    Button(action: engine.decreaseWPM) {
                        Text("−")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    
                    Text("\(Int(engine.wpm)) WPM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 64)
                    
                    Button(action: engine.increaseWPM) {
                        Text("+")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                
                // Progress
                if engine.hasContent {
                    VStack(spacing: 1) {
                        Text("\(Int(engine.progress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                        Text(engine.etaMinutes < 1 ? "<1 min" : "\(Int(engine.etaMinutes)) min left")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .frame(width: 60)
                }
                
                // Close Toolbar
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.leading, 8)
                .help("Hide Toolbar")
            }
        }
        .frame(height: 56)
        .preferredColorScheme(.dark)
    }
}

// MARK: - RSVP Overlay View
/// Advanced centered RSVP reading box, wrapped in dynamic glass themes with detailed options drawer.
struct RSVPOverlayView: View {
    @ObservedObject var engine: RSVPEngine
    let onClose: () -> Void

    @State private var showSettings = false
    @State private var isHovering = false

    var body: some View {
        let theme = engine.selectedTheme
        
        ZStack(alignment: .topTrailing) {
            // Subtly colored ambient backdrop glow that blurs through the glass
            RadialGradient(
                colors: [theme.accentColor.opacity(0.12), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 360
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            
            // True Zen Mode Fullscreen Dimmer Backdrop!
            if engine.zenMode {
                Color.black // Solid black base to completely block the behind-window blur
                    .ignoresSafeArea()
                Color.black.opacity(engine.backgroundDimOpacity + 0.1) // Custom user dimming opacity (plus extra)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            
            if engine.isLibraryMode {
                LocalLibraryView(engine: engine, onClose: onClose)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if showSettings && !engine.zenMode {
                SettingsView(engine: engine, onDismiss: {
                    withAnimation(.spring(response: 0.25)) {
                        showSettings = false
                    }
                })
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                VStack(spacing: 0) {
                    if engine.zenMode {
                        Spacer()
                    }
                    
                    // Header (Hidden in Zen Mode)
                    if !engine.zenMode {
                        headerBar(theme: theme)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                        
                        Divider().background(Color.white.opacity(0.08))
                    }
                    
                    // Main Word Box
                    wordDisplayBox(theme: theme)
                        .frame(maxWidth: .infinity)
                        .frame(height: engine.zenMode ? 260 : 180)
                        .cornerRadius(engine.zenMode ? 16 : 0)
                        .padding(.horizontal, engine.zenMode ? 40 : 0)
                    
                    // Footer controls (Hidden in Zen Mode)
                    if !engine.zenMode {
                        Divider().background(Color.white.opacity(0.08))
                        
                        // Advanced Progress Bar
                        progressBar(theme: theme)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                        
                        // Main Control Dashboard
                        controlsDashboard(theme: theme)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                    }
                    
                    if engine.zenMode {
                        Spacer()
                    }
                }
            }
            
            // Hover Overlay for Zen Mode Exit
            if !engine.isLibraryMode && engine.zenMode && isHovering {
                Button(action: {
                    withAnimation(.spring(response: 0.25)) {
                        engine.zenMode = false
                        engine.triggerHaptics(.generic)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.and.arrow.down.left.rectangle")
                        Text("Exit Zen")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .padding(16)
                .transition(.opacity)
            }
            
            // Premium Glassmorphic Loading Screen
            if engine.isLoading {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: theme.accentColor))
                            .scaleEffect(1.5)
                        
                        Text("Compiling content...")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Text("Extracting EPUB text & indexing for rapid reading...")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .frame(width: 280)
                    }
                    .padding(28)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header Bar
    private func headerBar(theme: GlassTheme) -> some View {
        HStack {
            // Close Button
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.35))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Overlay (Esc)")
            
            Spacer()
            
            // Title & Author Info
            VStack(spacing: 2) {
                Text(engine.bookTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                if !engine.bookAuthor.isEmpty {
                    Text(engine.bookAuthor)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // Library Bookshelf grid toggle
                Button(action: {
                    withAnimation(.spring(response: 0.25)) {
                        engine.isLibraryMode = true
                        engine.triggerHaptics(.generic)
                    }
                }) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Open Book Library")

                // Settings Drawer Toggle
                Button(action: {
                    withAnimation(.spring(response: 0.25)) {
                        showSettings.toggle()
                        engine.triggerHaptics(.generic)
                    }
                }) {
                    Image(systemName: showSettings ? "slider.horizontal.3" : "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(showSettings ? theme.accentColor : .white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(showSettings ? theme.accentColor.opacity(0.12) : Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Reading Settings")

                // Zen Mode Trigger
                Button(action: {
                    withAnimation(.spring(response: 0.25)) {
                        showSettings = false
                        engine.zenMode = true
                        engine.triggerHaptics(.generic)
                    }
                }) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Zen Mode (Z)")
            }
        }
    }

    // MARK: - Word Box
    private var orpGuideLine: some View {
        VStack {
            Spacer().frame(height: 12)
            // Top marker triangle
            Image(systemName: "triangle.fill")
                .font(.system(size: 6))
                .foregroundColor(engine.selectedTheme.accentColor.opacity(0.6))
                .rotationEffect(.degrees(180))
            Spacer()
            // Sleek glowing vertical guide line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, engine.selectedTheme.accentColor.opacity(0.24), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 1.5)
            Spacer()
            // Bottom marker triangle
            Image(systemName: "triangle.fill")
                .font(.system(size: 6))
                .foregroundColor(engine.selectedTheme.accentColor.opacity(0.6))
            Spacer().frame(height: 12)
        }
    }

    private func wordDisplayBox(theme: GlassTheme) -> some View {
        ZStack {
            // Horizontal bounds guidelines (very subtle)
            VStack {
                Spacer()
                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
                Spacer().frame(height: 110)
                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
                Spacer()
            }
            
            // Vertical ORP static alignment guide
            if engine.showGuide && !engine.zenMode {
                orpGuideLine
            }
            
            // Word Output Area
            if engine.hasContent {
                if engine.displayMode == "Flow" && !engine.zenMode {
                    ContextStreamView(engine: engine, fontSize: CGFloat(engine.fontSize), accentColor: theme.accentColor)
                        .id(engine.currentIndex)
                        .transition(.opacity.animation(.easeInOut(duration: 0.03)))
                } else {
                    ORPWordView(word: engine.displayWord, fontFamily: engine.fontFamily, fontSize: CGFloat(engine.fontSize), accentColor: theme.accentColor)
                        .id(engine.currentIndex)
                        .transition(.opacity.animation(.easeInOut(duration: 0.03)))
                }
            } else {
                Text("Press Space to start reading")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .background(Color.black.opacity(0.12))
        .drawingGroup() // High efficiency rendering on GPU
    }

    // MARK: - Progress Scrubber
    private func progressBar(theme: GlassTheme) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background Track
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                
                // Active Track Gradient
                Capsule()
                    .fill(LinearGradient(colors: [theme.accentColor, theme.accentColor.opacity(0.6)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * engine.progress, height: 6)
                
                // Sleek Drag Knob
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: theme.accentColor.opacity(0.4), radius: 3)
                    .offset(x: geo.size.width * engine.progress - 7)
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                engine.seekTo(v.location.x / geo.size.width)
            })
        }
        .frame(height: 14)
    }

    // MARK: - Controls Dashboard
    private func controlsDashboard(theme: GlassTheme) -> some View {
        HStack(spacing: 20) {
            // Numeric Reading Index Progress
            Text("\(engine.currentIndex + 1) / \(engine.wordCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 90, alignment: .leading)
            
            Spacer()
            
            // Skip Back 15 Words
            ctrlBtn("backward.fill") { engine.skipBack() }
                .help("Rewind 15 words (←)")
            
            // Play / Pause Circle Capsule Button
            Button(action: { engine.togglePlayPause() }) {
                ZStack {
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 46, height: 46)
                        .shadow(color: theme.accentColor.opacity(0.45), radius: 8)
                    
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: engine.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(engine.isPlaying ? 0.96 : 1.04)
            .animation(.spring(response: 0.22, dampingFraction: 0.5), value: engine.isPlaying)
            .help("Play / Pause (Space)")
            
            // Skip Forward 15 Words
            ctrlBtn("forward.fill") { engine.skipForward() }
                .help("Forward 15 words (→)")
            
            Spacer()
            
            // Speed adjustments (Visual Dial Slider)
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.needle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                
                WPMSlider(value: $engine.wpm, range: 60...800, accentColor: theme.accentColor)
                    .frame(width: 80)
                
                Text("\(Int(engine.wpm))")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 28, alignment: .trailing)
                
                Text("WPM")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    private func ctrlBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .overlay(Circle().stroke(Color.white.opacity(0.04), lineWidth: 1))
        }.buttonStyle(.plain)
    }

}

// MARK: - ORP Split View Components
struct ORPWordView: View {
    let word: String
    let fontFamily: String
    let fontSize: CGFloat
    let accentColor: Color
    
    var body: some View {
        let (prefix, focus, suffix) = ORPCalculator.split(word)
        
        HStack(spacing: 0) {
            // Left side (Prefix) aligned to trailing edge
            HStack(spacing: 0) {
                Spacer()
                Text(prefix)
                    .font(fontDesign(fontFamily, size: fontSize, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(width: 320, alignment: .trailing)
            
            // Center (Focus letter) static alignment
            if let f = focus {
                Text(String(f))
                    .font(fontDesign(fontFamily, size: fontSize, weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: 36, alignment: .center)
            } else {
                Spacer().frame(width: 36)
            }
            
            // Right side (Suffix) aligned to leading edge
            HStack(spacing: 0) {
                Text(suffix)
                    .font(fontDesign(fontFamily, size: fontSize, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
            }
            .frame(width: 320, alignment: .leading)
        }
    }
    
    private func fontDesign(_ family: String, size: CGFloat, weight: Font.Weight) -> Font {
        switch family {
        case "Serif":
            return .custom("Georgia", size: size).weight(weight)
        case "Mono":
            return .system(size: size, weight: weight, design: .monospaced)
        default:
            return .system(size: size, weight: weight, design: .default)
        }
    }
}

// MARK: - Context Stream Flow View
struct ContextStreamView: View {
    @ObservedObject var engine: RSVPEngine
    let fontSize: CGFloat
    let accentColor: Color
    
    var body: some View {
        let currentIdx = engine.currentIndex
        let words = engine.words
        
        HStack(spacing: 20) {
            // Context stream trailing back words (index-2, index-1)
            HStack(spacing: 14) {
                Spacer()
                if currentIdx >= 2 {
                    Text(ORPCalculator.clean(words[currentIdx - 2]))
                        .font(fontDesign(engine.fontFamily, size: fontSize * 0.46, weight: .regular))
                        .foregroundColor(.white.opacity(0.12))
                        .lineLimit(1)
                }
                if currentIdx >= 1 {
                    Text(ORPCalculator.clean(words[currentIdx - 1]))
                        .font(fontDesign(engine.fontFamily, size: fontSize * 0.64, weight: .regular))
                        .foregroundColor(.white.opacity(0.36))
                        .lineLimit(1)
                }
            }
            .frame(width: 160, alignment: .trailing)
            
            // Main word at static ORP point
            ORPWordView(word: engine.displayWord, fontFamily: engine.fontFamily, fontSize: fontSize, accentColor: accentColor)
                .frame(width: 320)
            
            // Context stream leading forward words (index+1, index+2)
            HStack(spacing: 14) {
                if currentIdx + 1 < words.count {
                    Text(ORPCalculator.clean(words[currentIdx + 1]))
                        .font(fontDesign(engine.fontFamily, size: fontSize * 0.64, weight: .regular))
                        .foregroundColor(.white.opacity(0.36))
                        .lineLimit(1)
                }
                if currentIdx + 2 < words.count {
                    Text(ORPCalculator.clean(words[currentIdx + 2]))
                        .font(fontDesign(engine.fontFamily, size: fontSize * 0.46, weight: .regular))
                        .foregroundColor(.white.opacity(0.12))
                        .lineLimit(1)
                }
                Spacer()
            }
            .frame(width: 160, alignment: .leading)
        }
    }
    
    private func fontDesign(_ family: String, size: CGFloat, weight: Font.Weight) -> Font {
        switch family {
        case "Serif":
            return .custom("Georgia", size: size).weight(weight)
        case "Mono":
            return .system(size: size, weight: weight, design: .monospaced)
        default:
            return .system(size: size, weight: weight, design: .default)
        }
    }
}

// MARK: - WPMSlider
struct WPMSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accentColor: Color
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 4)
                
                // Active highlight track
                Capsule()
                    .fill(accentColor)
                    .frame(width: geo.size.width * CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)), height: 4)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: accentColor.opacity(0.3), radius: 2)
                    .offset(x: geo.size.width * CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) - 6)
            }
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let fraction = drag.location.x / geo.size.width
                    let newValue = range.lowerBound + min(max(fraction, 0.0), 1.0) * (range.upperBound - range.lowerBound)
                    let steppedValue = (newValue / 25.0).rounded() * 25.0 // Snap to 25 WPM steps
                    if steppedValue != value {
                        value = min(max(steppedValue, range.lowerBound), range.upperBound)
                    }
                }
            )
        }
        .frame(height: 12)
    }
}

// MARK: - Toggle Switch Component
struct CustomToggleStyle: ToggleStyle {
    let accentColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isOn ? accentColor : Color.white.opacity(0.12))
                    .frame(width: 30, height: 18)
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .shadow(radius: 1)
                            .offset(x: configuration.isOn ? 6 : -6)
                            .animation(.spring(response: 0.2), value: configuration.isOn)
                    )

                configuration.label

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Drawer Panel
struct SettingsView: View {
    @ObservedObject var engine: RSVPEngine
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(engine.selectedTheme.accentColor)
                    Text("FOCUS READER CONFIGURATION")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Button(action: {
                    engine.triggerHaptics(.generic)
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(engine.selectedTheme.accentColor.opacity(0.2)))
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Close Settings (Esc)")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider().background(Color.white.opacity(0.08))
            
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 32) {
                    // Left Column: Look & Feel
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("TYPOGRAPHY STYLE")
                            HStack(spacing: 8) {
                                fontButton("Serif", label: "Serif")
                                fontButton("Sans", label: "Sans")
                                fontButton("Mono", label: "Mono")
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("FONT SIZE")
                            HStack(spacing: 8) {
                                sizeButton(40.0, label: "S")
                                sizeButton(52.0, label: "M")
                                sizeButton(64.0, label: "L")
                                sizeButton(80.0, label: "XL")
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("GLASS BACKING THEME")
                            HStack(spacing: 12) {
                                ForEach(GlassTheme.allCases) { theme in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.25)) {
                                            engine.selectedTheme = theme
                                            engine.triggerHaptics(.generic)
                                        }
                                    }) {
                                        Circle()
                                            .fill(theme.accentColor)
                                            .frame(width: 26, height: 26)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white, lineWidth: engine.selectedTheme == theme ? 2 : 0)
                                            )
                                            .shadow(color: theme.accentColor.opacity(0.4), radius: engine.selectedTheme == theme ? 5 : 0)
                                    }
                                    .buttonStyle(.plain)
                                    .help(theme.rawValue)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("DISPLAY MECHANISM")
                            HStack(spacing: 8) {
                                modeButton("Single", label: "Single Focus")
                                modeButton("Flow", label: "Context Flow")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Divider Line
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                    
                    // Right Column: Advanced Mechanics & Pacing
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("INTERACTIVE VISUAL GUIDES")
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $engine.showGuide) {
                                    Text("Optimal Alignment Guide")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .toggleStyle(CustomToggleStyle(accentColor: engine.selectedTheme.accentColor))
                                
                                Toggle(isOn: $engine.smartPacing) {
                                    Text("Smart Sentence Pacing")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .toggleStyle(CustomToggleStyle(accentColor: engine.selectedTheme.accentColor))
                                
                                Toggle(isOn: $engine.enableHaptics) {
                                    Text("Tactile Haptic Feedback")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .toggleStyle(CustomToggleStyle(accentColor: engine.selectedTheme.accentColor))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                sectionLabel("PUNCTUATION DELAY MULTIPLIER")
                                Spacer()
                                Text(String(format: "%.1fx", engine.punctuationPauseMultiplier))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(engine.selectedTheme.accentColor)
                            }
                            Slider(value: $engine.punctuationPauseMultiplier, in: 1.0...3.0, step: 0.1)
                                .accentColor(engine.selectedTheme.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                sectionLabel("ZEN BACKGROUND DIMMING")
                                Spacer()
                                Text(String(format: "%d%%", Int(engine.backgroundDimOpacity * 100)))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(engine.selectedTheme.accentColor)
                            }
                            Slider(value: $engine.backgroundDimOpacity, in: 0.1...0.9, step: 0.05)
                                .accentColor(engine.selectedTheme.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .frame(width: 740, height: 400)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
    
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
    }
    
    private func fontButton(_ family: String, label: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                engine.fontFamily = family
                engine.triggerHaptics(.generic)
            }
        }) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(engine.fontFamily == family ? .white : .white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(engine.fontFamily == family ? engine.selectedTheme.accentColor : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
    
    private func sizeButton(_ size: Double, label: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                engine.fontSize = size
                engine.triggerHaptics(.generic)
            }
        }) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(engine.fontSize == size ? .white : .white.opacity(0.6))
                .frame(width: 38, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(engine.fontSize == size ? engine.selectedTheme.accentColor : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
    
    private func modeButton(_ mode: String, label: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                engine.displayMode = mode
                engine.triggerHaptics(.generic)
            }
        }) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(engine.displayMode == mode ? .white : .white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(engine.displayMode == mode ? engine.selectedTheme.accentColor : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Local Library View
struct LocalLibraryView: View {
    @ObservedObject var engine: RSVPEngine
    let onClose: () -> Void
    
    @State private var booksAppRunning: Bool = false
    
    var body: some View {
        let theme = engine.selectedTheme
        
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.35))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close Library (Esc)")
                
                Spacer()
                
                Text("Local EPUB Library")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                HStack(spacing: 10) {
                    Button(action: selectLibraryFolder) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus")
                            Text("Pick Folder")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Select folder containing EPUB books")
                    
                    if engine.hasContent {
                        Button(action: {
                            withAnimation(.spring(response: 0.25)) {
                                engine.isLibraryMode = false
                                engine.triggerHaptics(.generic)
                            }
                        }) {
                            Image(systemName: "arrow.left.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Back to reading")
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider().background(Color.white.opacity(0.08))
            
            // Check if Apple Books is open/running and show quick pickup card
            if booksAppRunning {
                booksPickupCard(theme: theme)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }
            
            if engine.localLibrary.isEmpty {
                emptyStateView(theme: theme)
            } else {
                booksGridView(theme: theme)
            }
        }
        .onAppear {
            checkBooksAppStatus()
        }
    }
    
    private func checkBooksAppStatus() {
        booksAppRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.iBooksX" }
    }
    
    // Quick pickup card if Apple Books is running
    private func booksPickupCard(theme: GlassTheme) -> some View {
        Button(action: {
            engine.isLibraryMode = false
            engine.triggerHaptics(.generic)
            NotificationCenter.default.post(name: NSNotification.Name("com.focusreader.readActiveBook"), object: nil)
        }) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(theme.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pick up from active Book in Apple Books")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    Text("Read in real-time from your open book in Books app.")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.accentColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(theme.accentColor.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func emptyStateView(theme: GlassTheme) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 72, height: 72)
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.35))
            }
            
            VStack(spacing: 4) {
                Text("No local books loaded")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                Text("Choose a directory with EPUB files to compile your bookshelf.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .frame(width: 320)
            }
            
            Button(action: selectLibraryFolder) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                    Text("Select Books Folder")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(theme.accentColor))
                .shadow(color: theme.accentColor.opacity(0.3), radius: 6)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
    }
    
    private func booksGridView(theme: GlassTheme) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            let columns = [
                GridItem(.flexible(), spacing: 18),
                GridItem(.flexible(), spacing: 18)
            ]
            
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(engine.localLibrary) { book in
                    bookCard(book, theme: theme)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }
    
    private func bookCard(_ book: LocalBook, theme: GlassTheme) -> some View {
        Button(action: {
            engine.loadLocalBook(book)
            engine.triggerHaptics(.generic)
        }) {
            HStack(spacing: 12) {
                // Frosted/gradient book cover
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [theme.accentColor.opacity(0.4), theme.accentColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    
                    Image(systemName: "book.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    
                    Text(book.author)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                    
                    Spacer().frame(height: 2)
                    
                    HStack(spacing: 8) {
                        // Small reading progress percentage
                        Text("\(Int(book.readingProgress * 100))% read")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.accentColor.opacity(0.8))
                        
                        // Mini inline progress bar
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08)).frame(width: 40, height: 3)
                            Capsule().fill(theme.accentColor).frame(width: 40 * CGFloat(book.readingProgress), height: 3)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func selectLibraryFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Select a folder containing EPUB books"
        panel.level = .statusBar
        
        if panel.runModal() == .OK, let url = panel.url {
            engine.scanFolder(at: url.path)
        }
    }
}
