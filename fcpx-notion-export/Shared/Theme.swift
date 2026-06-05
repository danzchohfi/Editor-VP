import Cocoa

/// Identidade visual centralizada. Para casar 100% com a Produção.app,
/// ajuste apenas os hex e as fontes abaixo (https://www.producao.app/identidade).
enum Brand {

    // MARK: - Cores — identidade Vitamina (producao.app)
    static let background   = NSColor(hex: "#08100E")   // preto esverdeado
    static let surface      = NSColor(hex: "#111A17")   // cartões / campos
    static let surfaceAlt   = NSColor(hex: "#1A2521")   // hover / linhas
    static let accent       = NSColor(hex: "#15594D")   // verde-petróleo (CTA preenchido)
    static let accentHover  = NSColor(hex: "#1C6E5F")
    static let accentBright = NSColor(hex: "#2FB293")   // verde vivo (ponto / destaques)
    static let textPrimary  = NSColor(hex: "#F2F6F4")
    static let textMuted    = NSColor(hex: "#8B968F")
    static let border       = NSColor(hex: "#242E2A")
    static let success      = NSColor(hex: "#2FB293")
    static let danger       = NSColor(hex: "#E8635E")

    // MARK: - Tipografia (sans pesada no display, como o site)
    static func display(_ size: CGFloat = 22) -> NSFont { .systemFont(ofSize: size, weight: .heavy) }
    static func semibold(_ size: CGFloat = 14) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }
    static func body(_ size: CGFloat = 13) -> NSFont { .systemFont(ofSize: size, weight: .regular) }

    static let radius: CGFloat = 12

    /// Wordmark "vitamina." com o ponto na cor de marca.
    static func wordmark(size: CGFloat = 24) -> NSTextField {
        let heavy = NSFont.systemFont(ofSize: size, weight: .heavy)
        let mark = NSMutableAttributedString(string: "vitamina", attributes: [
            .font: heavy, .foregroundColor: textPrimary, .kern: -0.5
        ])
        mark.append(NSAttributedString(string: ".", attributes: [
            .font: heavy, .foregroundColor: accentBright
        ]))
        let label = NSTextField(labelWithAttributedString: mark)
        label.isSelectable = false
        return label
    }

    // MARK: - Componentes reutilizáveis

    /// Botão preenchido com a cor de marca.
    static func primaryButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = HoverButton(title: title, target: target, action: action)
        button.fill = accent
        button.hoverFill = accentHover
        button.titleColor = .white
        button.font = semibold(14)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return button
    }

    /// Botão discreto (contorno), para ações secundárias.
    static func ghostButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = HoverButton(title: title, target: target, action: action)
        button.fill = .clear
        button.hoverFill = surfaceAlt
        button.titleColor = textMuted
        button.borderColor = border
        button.font = semibold(13)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return button
    }

    /// Campo de texto estilizado (com padding interno e fundo de superfície).
    static func field(placeholder: String, secure: Bool = false) -> NSTextField {
        let field: NSTextField = secure ? PaddedSecureField() : PaddedTextField()
        field.placeholderString = placeholder
        field.font = body(13)
        field.textColor = textPrimary
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.backgroundColor = surface.cgColor
        field.layer?.cornerRadius = 10
        field.layer?.borderWidth = 1
        field.layer?.borderColor = border.cgColor
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return field
    }

    static func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        return label
    }

    /// Envolve uma view num cartão arredondado com borda.
    static func cardContainer(_ content: NSView, padding: CGFloat = 0) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = surface.cgColor
        box.layer?.cornerRadius = radius
        box.layer?.borderWidth = 1
        box.layer?.borderColor = border.cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -padding),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -padding)
        ])
        return box
    }
}

// MARK: - Controles customizados

/// Botão com fundo arredondado e estado de hover.
final class HoverButton: NSButton {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var hoverFill: NSColor = .clear
    var borderColor: NSColor? { didSet { needsDisplay = true } }
    var titleColor: NSColor = .white { didSet { applyTitle() } }
    var font: NSFont = .systemFont(ofSize: 13) { didSet { applyTitle() } }
    private var hovering = false
    private var trackingAreaRef: NSTrackingArea?

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        applyTitle()
    }

    private func setup() {
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
    }

    private func applyTitle() {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: titleColor, .font: font
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingAreaRef = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let color = hovering ? hoverFill : fill
        color.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        path.fill()
        if let border = borderColor {
            border.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        super.draw(dirtyRect)
    }
}

/// NSTextField com padding interno horizontal.
final class PaddedTextField: NSTextField {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12) }
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: rect.insetBy(dx: 12, dy: 0))
    }
}
final class PaddedSecureField: NSSecureTextField {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12) }
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: rect.insetBy(dx: 12, dy: 0))
    }
}

/// Linha da tabela de cards com seleção/hover na cor de marca.
final class BrandRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        Brand.accentBright.withAlphaComponent(0.20).setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 2), xRadius: 8, yRadius: 8)
        path.fill()
    }
}

extension NSColor {
    /// Cria uma cor a partir de um hex "#RRGGBB" (ou "RRGGBB").
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((value & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(value & 0x0000FF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
