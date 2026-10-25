import SimpleVectorizerCore
import SwiftUI

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    init(_ title: String) {
        self.title = title
        self.trailing = nil
    }

    init<V: View>(_ title: String, @ViewBuilder trailing: () -> V) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textFaint.swiftUI)
                .kerning(0.8)
                .textCase(.uppercase)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.bottom, 2)
    }
}

struct FieldRow<Content: View>: View {
    let label: String
    var width: CGFloat = 86
    let content: Content

    init(_ label: String, width: CGFloat = 86, @ViewBuilder content: () -> Content) {
        self.label = label
        self.width = width
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim.swiftUI)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
            content
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SliderRow: View {
    let label: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var tint: Color = Theme.accent.swiftUI

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(valueText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if let step {
                Slider(value: $value, in: range, step: step)
                    .tint(tint)
                    .controlSize(.small)
            } else {
                Slider(value: $value, in: range)
                    .tint(tint)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CommitField: View {
    let value: String
    var placeholder: String = ""
    var monospaced: Bool = false
    var onCommit: (String) -> Void
    var onSubmit: ((String) -> Void)? = nil

    @State private var text: String
    @FocusState private var focused: Bool

    init(
        value: String,
        placeholder: String = "",
        monospaced: Bool = false,
        onCommit: @escaping (String) -> Void,
        onSubmit: ((String) -> Void)? = nil
    ) {
        self.value = value
        self.placeholder = placeholder
        self.monospaced = monospaced
        self.onCommit = onCommit
        self.onSubmit = onSubmit
        self._text = State(initialValue: value)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 11.5, design: monospaced ? .monospaced : .default))
            .foregroundStyle(Theme.text.swiftUI)
            .focused($focused)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(focused ? Theme.accent.swiftUI.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .animation(.easeOut(duration: 0.15), value: focused)
            .onAppear { text = value }
            .onChange(of: value) { _, newValue in if !focused { text = newValue } }
            .onSubmit { onCommit(text); onSubmit?(text) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused && text != value { onCommit(text) }
            }
    }
}

struct IconButton: View {
    let symbol: String
    var helpText: String = ""
    var active: Bool = false
    var tint: Color = Theme.accent.swiftUI
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(disabled ? Theme.textFaint.swiftUI : (active ? Theme.background.swiftUI : Theme.text.swiftUI))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active ? tint : Color.white.opacity(disabled ? 0.02 : (hovering ? 0.1 : 0.06)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(helpText)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct TextButton: View {
    let title: String
    var symbol: String? = nil
    var prominent: Bool = false
    var destructive: Bool = false
    var tint: Color? = nil
    var compact: Bool = false
    var flexibleWidth: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let activeColor = tint ?? (destructive ? Theme.danger.swiftUI : Theme.accent.swiftUI)
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: compact ? 10.5 : 11.5, weight: prominent || destructive ? .semibold : .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: flexibleWidth ? .infinity : nil)
            .fixedSize(horizontal: !flexibleWidth, vertical: false)
            .foregroundStyle(
                disabled ? Theme.textFaint.swiftUI
                    : (prominent || destructive ? Theme.background.swiftUI : (tint ?? Theme.text.swiftUI))
            )
            .padding(.horizontal, compact ? 7 : 11)
            .padding(.vertical, compact ? 4 : 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        prominent || destructive ? activeColor.opacity(disabled ? 0.35 : (hovering ? 0.9 : 1))
                            : (tint != nil ? activeColor.opacity(hovering ? 0.22 : 0.14) : Color.white.opacity(disabled ? 0.02 : (hovering ? 0.11 : 0.07)))
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct Chip: View {
    let text: String
    var tint: Color = Theme.textDim.swiftUI
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(filled ? Theme.background.swiftUI : tint)
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(filled ? tint : tint.opacity(0.14))
            )
            .lineLimit(1)
    }
}

struct ActionChip: View {
    let text: String
    var tint: Color = Theme.textDim.swiftUI
    var active: Bool = false
    var help: String = ""
    var action: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        if let action {
            Button(action: action) {
                Chip(text: text, tint: tint, filled: active || hovering)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
        } else {
            Chip(text: text, tint: tint, filled: active).help(help)
        }
    }
}

struct ScanProgressBar: View {
    let fraction: Double
    let active: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(active ? 0.05 : 0))
                Rectangle()
                    .fill(Theme.accent.swiftUI)
                    .frame(width: max(0, width * (active ? fraction : 0)))
                    .animation(.linear(duration: 0.12), value: fraction)
            }
        }
        .frame(height: 2)
        .opacity(active ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: active)
    }
}

/// Vector hero illustration for the empty state and About sheet:
/// pixel staircase on the left morphing into a smooth amber/cyan cubic Bézier curve with control handles and AxiDraw pen nib.
struct VectorizerHeroGraphic: View {
    var active: Bool = false
    var size: CGFloat = 120

    var body: some View {
        Canvas { ctx, s in
            let w = s.width
            let h = s.height

            // Subtle outer ring
            let ringRect = CGRect(x: 6, y: 6, width: w - 12, height: h - 12)
            ctx.stroke(Path(ellipseIn: ringRect), with: .color(Theme.accent.swiftUI.opacity(0.18)), lineWidth: 1.2)

            // Faint pixel grid blocks on the left (bitmap input)
            let cell = w * 0.085
            for k in 0..<5 {
                let rx = w * 0.16 + CGFloat(k) * (cell * 0.78)
                let ry = h * 0.68 - CGFloat(k) * (cell * 0.62)
                let rect = CGRect(x: rx, y: ry, width: cell, height: cell)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Theme.textFaint.swiftUI.opacity(0.32)))
            }

            // Bézier tangent handles (cyan)
            let p0 = CGPoint(x: w * 0.18, y: h * 0.72)
            let c1 = CGPoint(x: w * 0.34, y: h * 0.18)
            let c2 = CGPoint(x: w * 0.68, y: h * 0.84)
            let p3 = CGPoint(x: w * 0.84, y: h * 0.28)

            var handles = Path()
            handles.move(to: p0)
            handles.addLine(to: c1)
            handles.move(to: p3)
            handles.addLine(to: c2)
            ctx.stroke(handles, with: .color(Theme.tcp.swiftUI.opacity(0.65)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))

            // Smooth cubic Bézier curve (amber)
            var curve = Path()
            curve.move(to: p0)
            curve.addCurve(to: p3, control1: c1, control2: c2)
            ctx.stroke(curve, with: .color(Theme.accent.swiftUI), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))

            // Control point diamonds/circles
            for pt in [c1, c2] {
                let r = CGRect(x: pt.x - 3.2, y: pt.y - 3.2, width: 6.4, height: 6.4)
                ctx.fill(Path(ellipseIn: r), with: .color(Theme.tcp.swiftUI))
            }
            for pt in [p0, p3] {
                let r = CGRect(x: pt.x - 4.0, y: pt.y - 4.0, width: 8.0, height: 8.0)
                ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(Theme.alive.swiftUI))
            }
        }
        .frame(width: size, height: size)
    }
}
