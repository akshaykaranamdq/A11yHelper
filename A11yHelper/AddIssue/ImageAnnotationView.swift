import SwiftUI
import UIKit

// MARK: - Model + renderer

enum AnnotationKind: Hashable { case rectangle, arrow }

/// Any stroke color. A few presets are offered for speed, and the system color picker covers the rest.
/// Red is the default.
struct AnnotationColor: Hashable {
    var r: Double
    var g: Double
    var b: Double

    static let red = AnnotationColor(r: 1.0, g: 0.23, b: 0.19)
    static let orange = AnnotationColor(r: 1.0, g: 0.58, b: 0.0)
    static let yellow = AnnotationColor(r: 1.0, g: 0.80, b: 0.0)
    static let green = AnnotationColor(r: 0.20, g: 0.78, b: 0.35)
    static let blue = AnnotationColor(r: 0.0, g: 0.48, b: 1.0)
    static let white = AnnotationColor(r: 1, g: 1, b: 1)
    static let black = AnnotationColor(r: 0, g: 0, b: 0)

    static let presets: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue, .white, .black]

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    /// From the system color picker.
    init(ui: UIColor) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(r: Double(red), g: Double(green), b: Double(blue))
    }

    var color: Color { Color(red: r, green: g, blue: b) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
    var isPreset: Bool { Self.presets.contains(self) }

    var name: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .white: "White"
        case .black: "Black"
        default: "Custom color"
        }
    }
}

/// Points are normalized (0...1) relative to the image, so they survive any display size.
struct Annotation: Identifiable, Equatable {
    var id = UUID()
    var kind: AnnotationKind
    var start: CGPoint
    var end: CGPoint
    var color: AnnotationColor = .red
}

enum AnnotationRenderer {
    static func strokeWidth(for imageSize: CGSize) -> CGFloat {
        max(3, max(imageSize.width, imageSize.height) * 0.005)
    }

    static func arrowHead(from s: CGPoint, to e: CGPoint, length: CGFloat) -> (CGPoint, CGPoint) {
        let angle = atan2(e.y - s.y, e.x - s.x)
        let spread = CGFloat.pi / 7
        return (
            CGPoint(x: e.x - length * cos(angle - spread), y: e.y - length * sin(angle - spread)),
            CGPoint(x: e.x - length * cos(angle + spread), y: e.y - length * sin(angle + spread))
        )
    }

    /// Flattens annotations onto the original image at full resolution.
    static func render(_ image: UIImage, _ annotations: [Annotation]) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let lineWidth = strokeWidth(for: size)

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            for a in annotations {
                a.color.uiColor.setStroke()
                let s = CGPoint(x: a.start.x * size.width, y: a.start.y * size.height)
                let e = CGPoint(x: a.end.x * size.width, y: a.end.y * size.height)
                let path = UIBezierPath()
                path.lineWidth = lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                switch a.kind {
                case .rectangle:
                    path.append(UIBezierPath(rect: CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                                                          width: abs(e.x - s.x), height: abs(e.y - s.y))))
                case .arrow:
                    let (h1, h2) = arrowHead(from: s, to: e, length: lineWidth * 5)
                    path.move(to: s); path.addLine(to: e)
                    path.move(to: e); path.addLine(to: h1)
                    path.move(to: e); path.addLine(to: h2)
                }
                path.stroke()
            }
        }
    }
}

// MARK: - Editor

private enum EditorTool: Hashable {
    case rectangle, arrow, select

    var kind: AnnotationKind? {
        switch self {
        case .rectangle: .rectangle
        case .arrow: .arrow
        case .select: nil
        }
    }
}

/// Corner handles. For arrows only c0 (tail) and c2 (head) exist.
/// c0 = start, c1 = (end.x, start.y), c2 = end, c3 = (start.x, end.y)
private enum Handle: Hashable { case c0, c1, c2, c3 }

private enum DragMode {
    case idle, ignore, create
    case resize(Handle, UUID)
    case move(Annotation)
}

struct ImageAnnotationView: View {
    let image: UIImage
    let onDone: ([Annotation]) -> Void

    @State private var annotations: [Annotation]
    @State private var history: [[Annotation]] = []
    @State private var draft: Annotation?
    @State private var selectedID: UUID?
    /// nil until the user picks a shape option; the color palette only shows after that.
    @State private var tool: EditorTool?
    @State private var currentColor: AnnotationColor = .red
    @State private var lastColorEdit: (id: UUID, at: Date)?
    @State private var showColorPicker = false
    @State private var dragMode: DragMode = .idle
    @State private var dragSnapshot: [Annotation] = []
    @Environment(\.dismiss) private var dismiss
    @Namespace private var toolNamespace

    private let handleHitRadius: CGFloat = 28

    init(image: UIImage, annotations: [Annotation], onDone: @escaping ([Annotation]) -> Void) {
        self.image = image
        self.onDone = onDone
        _annotations = State(initialValue: annotations)
    }

    /// Always names the active tool so it's clear what a drag will do.
    private var hint: String {
        switch tool {
        case .rectangle: "Box: drag to draw"
        case .arrow: "Arrow: drag to draw"
        case .select: selectedID == nil
            ? "Select: tap a shape"
            : "Drag to move, drag the handles to resize"
        case nil: selectedID == nil
            ? "Pick Box or Arrow to start marking"
            : "Drag to move, drag the handles to resize"
        }
    }

    /// Palette shows once a shape option is chosen, or while a shape is selected so it can be recolored.
    private var showsPalette: Bool {
        tool == .rectangle || tool == .arrow || selectedID != nil
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let rect = fitted(image.size, in: geo.size)
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityLabel("Screenshot being annotated")

                    Canvas { ctx, _ in
                        for a in annotations + (draft.map { [$0] } ?? []) {
                            draw(a, in: rect, ctx: ctx)
                        }
                        if draft == nil, let id = selectedID,
                           let a = annotations.first(where: { $0.id == id }) {
                            drawSelection(a, in: rect, ctx: ctx)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
//                .contentShape(Rectangle())
                .gesture(drag(in: rect))
                .overlay(alignment: .top) {
                    Text(hint)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Edit image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(annotations)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: Bottom bar
    // Custom pills (system toolbar items ignore custom selection styling).

    /// The selected shape's color if there is one, otherwise the color for new shapes.
    private var activeColor: AnnotationColor {
        if let id = selectedID, let a = annotations.first(where: { $0.id == id }) { return a.color }
        return currentColor
    }

    /// Sets the color for new shapes, and recolors the selected shape if there is one.
    private func pickColor(_ c: AnnotationColor) {
        currentColor = c
        if let id = selectedID, let i = annotations.firstIndex(where: { $0.id == id }),
           annotations[i].color != c {
            // The system picker fires continuously while dragging, so group rapid changes into one undo step.
            let now = Date()
            if let last = lastColorEdit, last.id == id, now.timeIntervalSince(last.at) < 1.5 {
                // same recolor gesture: no new undo step
            } else {
                history.append(annotations)
            }
            lastColorEdit = (id, now)
            annotations[i].color = c
        }
    }

    /// Multicolor swatch that opens the system color picker. Once a custom color is chosen,
    /// the swatch shows that color (with a ring); otherwise it stays rainbow.
    private var customColorSwatch: some View {
        let isCustom = !activeColor.isPreset
        return Button {
            showColorPicker = true
        } label: {
            // Rainbow disc; once a custom color is chosen, that color shows in the center.
            Circle()
                .fill(AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                    center: .center))
                .frame(width: 24, height: 24)
                .overlay {
                    if isCustom {
                        Circle()
                            .fill(activeColor.color)
                            .padding(5)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5).padding(5))
                    }
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
                .overlay {
                    if isCustom { Circle().strokeBorder(.white, lineWidth: 2).padding(-4) }
                }
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Custom color")
        .accessibilityAddTraits(isCustom ? .isSelected : [])
        .sheet(isPresented: $showColorPicker) {
            SystemColorPicker(initial: activeColor.uiColor,
                              onChange: { pickColor(AnnotationColor(ui: $0)) },
                              onFinish: { showColorPicker = false })
                .overlay(alignment: .topTrailing) {
                    // The picker only draws its own close button when presented by UIKit, so add one.
                    CloseButton { showColorPicker = false }
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                }
                .presentationDetents([.medium, .large])
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationColor.presets, id: \.self) { c in
                let isSelected = activeColor == c
                Button { pickColor(c) } label: {
                    Circle()
                        .fill(c.color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
                        .overlay {
                            if isSelected {
                                Circle().strokeBorder(.white, lineWidth: 2).padding(-4)
                            }
                        }
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(c.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }

            customColorSwatch
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .pillBackground()
        .sensoryFeedback(.selection, trigger: activeColor)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if showsPalette {
                colorPicker
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            toolsRow
        }
        .animation(.snappy(duration: 0.25), value: showsPalette)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var toolsRow: some View {
        HStack {
            HStack(spacing: 0) {
                toolButton(.rectangle, icon: "square", label: "Draw box")
                toolButton(.arrow, icon: "arrow.up.right", label: "Draw arrow")
                toolButton(.select, icon: "cursorarrow", label: "Select and edit")
            }
            .padding(4)
            .pillBackground()

            Spacer()

            HStack(spacing: 0) {
                actionButton("arrow.uturn.backward", "Undo", disabled: history.isEmpty, action: undo)
                actionButton("trash", "Delete selected", disabled: selectedID == nil, action: deleteSelected)
                Menu {
                    Button("Clear all", role: .destructive, action: clearAll)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(width: 52, height: 44)
                }
                .disabled(annotations.isEmpty)
                .opacity(annotations.isEmpty ? 0.35 : 1)
            }
            .foregroundStyle(.white)
            .padding(4)
            .pillBackground()
        }
    }

    /// Selected tool: filled highlight that slides between options, plus accent color and bold weight.
    private func toolButton(_ t: EditorTool, icon: String, label: String) -> some View {
        let isSelected = tool == t
        return Button {
            withAnimation(.snappy(duration: 0.2)) { tool = t }
        } label: {
            Label(label, systemImage: icon)
                .labelStyle(.iconOnly)
                .font(.title3)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : Color.white)
                .frame(width: 52, height: 44)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .matchedGeometryEffect(id: "toolHighlight", in: toolNamespace)
                    }
                }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func actionButton(_ icon: String, _ label: String, disabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 52, height: 44)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    // MARK: Actions

    private func undo() {
        guard let previous = history.popLast() else { return }
        annotations = previous
        if let id = selectedID, !annotations.contains(where: { $0.id == id }) { selectedID = nil }
    }

    private func deleteSelected() {
        guard let id = selectedID else { return }
        history.append(annotations)
        annotations.removeAll { $0.id == id }
        selectedID = nil
    }

    private func clearAll() {
        history.append(annotations)
        annotations.removeAll()
        selectedID = nil
    }

    // MARK: Gesture

    private func drag(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if case .idle = dragMode { beginDrag(at: v.startLocation, in: rect) }
                let p = normalize(v.location, in: rect)

                switch dragMode {
                case .create:
                    if let kind = tool?.kind {
                        draft = Annotation(id: draft?.id ?? UUID(),
                                           kind: kind,
                                           start: normalize(v.startLocation, in: rect),
                                           end: p,
                                           color: currentColor)
                    }
                case .resize(let handle, let id):
                    update(id) { apply(handle, to: &$0, point: p) }
                case .move(let original):
                    var dx = v.translation.width / rect.width
                    var dy = v.translation.height / rect.height
                    dx = min(max(dx, -min(original.start.x, original.end.x)),
                             1 - max(original.start.x, original.end.x))
                    dy = min(max(dy, -min(original.start.y, original.end.y)),
                             1 - max(original.start.y, original.end.y))
                    update(original.id) {
                        $0.start = CGPoint(x: original.start.x + dx, y: original.start.y + dy)
                        $0.end = CGPoint(x: original.end.x + dx, y: original.end.y + dy)
                    }
                case .idle, .ignore:
                    break
                }
            }
            .onEnded { v in endDrag(at: v.startLocation, in: rect) }
    }

    private func beginDrag(at start: CGPoint, in rect: CGRect) {
        dragSnapshot = annotations

        // A selected shape's handles win in every tool.
        if let id = selectedID,
           let a = annotations.first(where: { $0.id == id }),
           let handle = hitHandle(a, at: start, in: rect) {
            dragMode = .resize(handle, id)
            return
        }

        // Dragging anywhere on the selected shape moves it, in every tool.
        if let id = selectedID,
           let a = annotations.first(where: { $0.id == id }),
           hits(a, at: start, in: rect) {
            dragMode = .move(a)
            return
        }

        if tool == nil || tool == .select {
            if let hit = annotations.last(where: { hits($0, at: start, in: rect) }) {
                selectedID = hit.id
                dragMode = .move(hit)
            } else {
                selectedID = nil
                dragMode = .ignore
            }
        } else {
            dragMode = .create
        }
    }

    private func endDrag(at start: CGPoint, in rect: CGRect) {
        switch dragMode {
        case .create:
            if let d = draft, hypot(d.end.x - d.start.x, d.end.y - d.start.y) > 0.01 {
                history.append(dragSnapshot)
                annotations.append(d)
                selectedID = d.id            // handles appear so it can be tweaked right away
            } else {
                // A tap: select the shape under the finger, or deselect.
                selectedID = annotations.last(where: { hits($0, at: start, in: rect) })?.id
            }
        case .resize, .move:
            if annotations != dragSnapshot { history.append(dragSnapshot) }
        case .idle, .ignore:
            break
        }
        draft = nil
        dragMode = .idle
    }

    private func update(_ id: UUID, _ change: (inout Annotation) -> Void) {
        if let i = annotations.firstIndex(where: { $0.id == id }) { change(&annotations[i]) }
    }

    private func apply(_ handle: Handle, to a: inout Annotation, point p: CGPoint) {
        switch handle {
        case .c0: a.start = p
        case .c1: a.end.x = p.x; a.start.y = p.y
        case .c2: a.end = p
        case .c3: a.start.x = p.x; a.end.y = p.y
        }
    }

    // MARK: Hit testing (view coordinates)

    private func handles(for a: Annotation) -> [(Handle, CGPoint)] {
        switch a.kind {
        case .arrow:
            return [(.c0, a.start), (.c2, a.end)]
        case .rectangle:
            return [(.c0, a.start),
                    (.c1, CGPoint(x: a.end.x, y: a.start.y)),
                    (.c2, a.end),
                    (.c3, CGPoint(x: a.start.x, y: a.end.y))]
        }
    }

    private func hitHandle(_ a: Annotation, at p: CGPoint, in rect: CGRect) -> Handle? {
        handles(for: a).first { _, np in
            let c = toView(np, in: rect)
            return hypot(c.x - p.x, c.y - p.y) <= handleHitRadius
        }?.0
    }

    private func hits(_ a: Annotation, at p: CGPoint, in rect: CGRect) -> Bool {
        let s = toView(a.start, in: rect), e = toView(a.end, in: rect)
        switch a.kind {
        case .arrow:
            return distance(from: p, toSegment: s, e) <= 22
        case .rectangle:
            return CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                          width: abs(e.x - s.x), height: abs(e.y - s.y))
                .insetBy(dx: -14, dy: -14)
                .contains(p)
        }
    }

    private func distance(from p: CGPoint, toSegment s: CGPoint, _ e: CGPoint) -> CGFloat {
        let dx = e.x - s.x, dy = e.y - s.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - s.x, p.y - s.y) }
        let t = max(0, min(1, ((p.x - s.x) * dx + (p.y - s.y) * dy) / len2))
        return hypot(p.x - (s.x + t * dx), p.y - (s.y + t * dy))
    }

    // MARK: Geometry + drawing

    private func fitted(_ size: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / size.width, container.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func normalize(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: min(max((p.x - rect.minX) / rect.width, 0), 1),
                y: min(max((p.y - rect.minY) / rect.height, 0), 1))
    }

    private func toView(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    private func lineWidth(in rect: CGRect) -> CGFloat {
        AnnotationRenderer.strokeWidth(for: image.size) * rect.width / image.size.width
    }

    private func shapePath(_ a: Annotation, in rect: CGRect) -> Path {
        let s = toView(a.start, in: rect), e = toView(a.end, in: rect)
        var p = Path()
        switch a.kind {
        case .rectangle:
            p.addRect(CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                             width: abs(e.x - s.x), height: abs(e.y - s.y)))
        case .arrow:
            let (h1, h2) = AnnotationRenderer.arrowHead(from: s, to: e, length: lineWidth(in: rect) * 5)
            p.move(to: s); p.addLine(to: e)
            p.move(to: e); p.addLine(to: h1)
            p.move(to: e); p.addLine(to: h2)
        }
        return p
    }

    private func draw(_ a: Annotation, in rect: CGRect, ctx: GraphicsContext) {
        ctx.stroke(shapePath(a, in: rect), with: .color(a.color.color),
                   style: StrokeStyle(lineWidth: lineWidth(in: rect), lineCap: .round, lineJoin: .round))
    }

    private func drawSelection(_ a: Annotation, in rect: CGRect, ctx: GraphicsContext) {
        let path = shapePath(a, in: rect)
        let lw = lineWidth(in: rect)

        // Glow behind the shape, plus a light tint inside boxes.
        if a.kind == .rectangle {
            ctx.fill(path, with: .color(a.color.color.opacity(0.15)))
        }
        ctx.stroke(path, with: .color(a.color.color.opacity(0.4)),
                   style: StrokeStyle(lineWidth: lw + 8, lineCap: .round, lineJoin: .round))
        // Re-draw the shape's own stroke on top of the glow.
        ctx.stroke(path, with: .color(a.color.color),
                   style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))

        if a.kind == .rectangle {
            let s = toView(a.start, in: rect), e = toView(a.end, in: rect)
            let box = CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                             width: abs(e.x - s.x), height: abs(e.y - s.y)).insetBy(dx: -8, dy: -8)
            ctx.stroke(Path(box), with: .color(.blue),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        for (_, np) in handles(for: a) {
            let c = toView(np, in: rect)
            let dot = Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18))
            ctx.fill(dot, with: .color(.white))
            ctx.stroke(dot, with: .color(.blue), lineWidth: 2)
        }
    }
}

// MARK: - System color picker

/// Apple's color picker (spectrum, grid, sliders, eyedropper), shown in a sheet.
/// Reports changes live and tells us when the user closes it.
private struct SystemColorPicker: UIViewControllerRepresentable {
    let initial: UIColor
    let onChange: (UIColor) -> Void
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.selectedColor = initial
        picker.supportsAlpha = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIColorPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        let parent: SystemColorPicker
        init(_ parent: SystemColorPicker) { self.parent = parent }

        func colorPickerViewController(_ viewController: UIColorPickerViewController,
                                       didSelect color: UIColor, continuously: Bool) {
            parent.onChange(color)
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            parent.onFinish()
        }
    }
}
