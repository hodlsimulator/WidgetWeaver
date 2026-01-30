//
//  WidgetSpecAIService.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import FoundationModels

struct WidgetSpecAIGenerationResult {
    let spec: WidgetSpec
    let usedModel: Bool
    let note: String
}

// MARK: - Guided generation payloads

@Generable
struct WidgetSpecGenerationPayload {
    @Guide(description: "Short widget name. 1–24 characters. No emojis unless requested.")
    var name: String

    @Guide(description: "Primary widget text. Short, glanceable. No long sentences.")
    var primaryText: String

    @Guide(description: "Optional secondary text. Keep short. Use nil when not needed.")
    var secondaryText: String?

    @Guide(description: "Layout axis.", .anyOf(["vertical", "horizontal"]))
    var axis: String

    @Guide(description: "Overall alignment.", .anyOf(["leading", "centre", "trailing", "center"]))
    var alignment: String

    @Guide(description: "Spacing between elements (points).", .range(0.0...24.0))
    var spacing: Double

    @Guide(description: "Padding around content (points).", .range(0.0...24.0))
    var padding: Double

    @Guide(description: "Corner radius (points).", .range(0.0...44.0))
    var cornerRadius: Double

    @Guide(
        description: "Background token.",
        .anyOf(["plain", "accentGlow", "radialGlow", "solidAccent", "subtleMaterial", "aurora", "sunset", "midnight", "candy"])
    )
    var background: String

    @Guide(
        description: "Accent colour token.",
        .anyOf(["blue", "teal", "green", "orange", "red", "pink", "purple", "gray", "yellow", "indigo"])
    )
    var accent: String

    @Guide(
        description: "Primary font token.",
        .anyOf(["automatic", "title2", "title3", "headline", "subheadline", "footnote", "caption", "caption2"])
    )
    var primaryTextStyle: String

    @Guide(
        description: "Secondary font token.",
        .anyOf(["automatic", "title2", "title3", "headline", "subheadline", "footnote", "caption", "caption2"])
    )
    var secondaryTextStyle: String

    @Guide(description: "Optional SF Symbol name (e.g., sparkles, clock.fill). Use nil for none.")
    var symbolName: String?

    @Guide(description: "Symbol placement.", .anyOf(["beforeName", "aboveName"]))
    var symbolPlacement: String?

    @Guide(description: "Symbol size (points).", .range(8.0...96.0))
    var symbolSize: Double?

    @Guide(description: "Symbol weight.", .anyOf(["regular", "medium", "semibold", "bold"]))
    var symbolWeight: String?

    @Guide(description: "Symbol rendering mode.", .anyOf(["monochrome", "hierarchical", "multicolor"]))
    var symbolRenderingMode: String?

    @Guide(description: "Symbol tint.", .anyOf(["accent", "primary", "secondary"]))
    var symbolTint: String?
}

@Generable
struct WidgetSpecPatchPayload {
    @Guide(description: "Optional replacement widget name.")
    var name: String?

    @Guide(description: "Optional replacement primary text.")
    var primaryText: String?

    @Guide(description: "Optional replacement secondary text.")
    var secondaryText: String?

    @Guide(description: "Set true to remove secondary text.")
    var removeSecondaryText: Bool?

    @Guide(description: "Optional axis override.", .anyOf(["vertical", "horizontal"]))
    var axis: String?

    @Guide(description: "Optional alignment override.", .anyOf(["leading", "centre", "trailing", "center"]))
    var alignment: String?

    @Guide(description: "Optional spacing override (points).", .range(0.0...24.0))
    var spacing: Double?

    @Guide(description: "Optional primary line limit in Small.", .range(1...8))
    var primaryLineLimitSmall: Int?

    @Guide(description: "Optional primary line limit.", .range(1...10))
    var primaryLineLimit: Int?

    @Guide(description: "Optional secondary line limit.", .range(1...10))
    var secondaryLineLimit: Int?

    @Guide(description: "Optional padding override (points).", .range(0.0...24.0))
    var padding: Double?

    @Guide(description: "Optional corner radius override (points).", .range(0.0...44.0))
    var cornerRadius: Double?

    @Guide(
        description: "Optional background token.",
        .anyOf(["plain", "accentGlow", "radialGlow", "solidAccent", "subtleMaterial", "aurora", "sunset", "midnight", "candy"])
    )
    var background: String?

    @Guide(
        description: "Optional accent token.",
        .anyOf(["blue", "teal", "green", "orange", "red", "pink", "purple", "gray", "yellow", "indigo"])
    )
    var accent: String?

    @Guide(
        description: "Optional primary font token.",
        .anyOf(["automatic", "title2", "title3", "headline", "subheadline", "footnote", "caption", "caption2"])
    )
    var primaryTextStyle: String?

    @Guide(
        description: "Optional secondary font token.",
        .anyOf(["automatic", "title2", "title3", "headline", "subheadline", "footnote", "caption", "caption2"])
    )
    var secondaryTextStyle: String?

    @Guide(description: "Set true to remove the symbol.")
    var removeSymbol: Bool?

    @Guide(description: "Optional SF Symbol name.")
    var symbolName: String?

    @Guide(description: "Optional symbol placement.", .anyOf(["beforeName", "aboveName"]))
    var symbolPlacement: String?

    @Guide(description: "Optional symbol size (points).", .range(8.0...96.0))
    var symbolSize: Double?

    @Guide(description: "Optional symbol weight.", .anyOf(["regular", "medium", "semibold", "bold"]))
    var symbolWeight: String?

    @Guide(description: "Optional symbol rendering.", .anyOf(["monochrome", "hierarchical", "multicolor"]))
    var symbolRenderingMode: String?

    @Guide(description: "Optional symbol tint.", .anyOf(["accent", "primary", "secondary"]))
    var symbolTint: String?

    @Guide(description: "Set true to remove the image reference from the spec (does not delete the file).")
    var removeImage: Bool?
}

// MARK: - Service

@MainActor
final class WidgetSpecAIService {
    static let shared = WidgetSpecAIService()

    private let model: SystemLanguageModel
    private let session: LanguageModelSession

    private init() {
        self.model = SystemLanguageModel.default

        let instructions = """
        Role: widget designer for iOS home screen widgets.
        Rules:
        - Generated text must be short, glanceable, and suitable for WidgetKit.
        - Prefer good contrast and simple layouts.
        - Avoid emojis unless explicitly requested.
        - When asked for a structured payload, output only the payload (no prose, no markdown, no code fences).
        - Never include an image file name. Image is handled separately in-app.
        """

        self.session = LanguageModelSession(instructions: instructions)
    }

    static func availabilityMessage() -> String {
        let m = SystemLanguageModel.default
        switch m.availability {
        case .available:
            return "Apple Intelligence: Ready"
        case .unavailable(.deviceNotEligible):
            return "Apple Intelligence: Not supported on this device"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence: Turn on in Settings → General → Apple Intelligence"
        case .unavailable(.modelNotReady):
            return "Apple Intelligence: Model is downloading / not ready yet"
        case .unavailable(let other):
            return "Apple Intelligence: Unavailable (\(String(describing: other)))"
        }
    }

    func generateNewSpec(from prompt: String) async -> WidgetSpecAIGenerationResult {
        let trimmed = Self.clean(prompt, maxLength: 280, fallback: "")
        guard !trimmed.isEmpty else {
            let spec = WidgetSpecNormaliser.normalisedAIOutput(WidgetSpec.defaultSpec())
            return WidgetSpecAIGenerationResult(
                spec: spec,
                usedModel: false,
                note: "Empty prompt — used default template."
            )
        }

        guard WidgetWeaverFeatureFlags.aiEnabled else {
            let spec = WidgetSpecNormaliser.normalisedAIOutput(Self.fallbackNewSpec(prompt: trimmed))
            return WidgetSpecAIGenerationResult(
                spec: spec,
                usedModel: false,
                note: "AI disabled — used deterministic template."
            )
        }

        switch model.availability {
        case .available:
            do {
                let response = try await session.respond(
                    to: Self.newSpecPrompt(userPrompt: trimmed),
                    generating: WidgetSpecGenerationPayload.self
                )
                let payload = response.content
                let spec = WidgetSpecNormaliser.normalisedAIOutput(Self.widgetSpec(from: payload))
                return WidgetSpecAIGenerationResult(spec: spec, usedModel: true, note: "Generated from prompt.")
            } catch {
                let spec = WidgetSpecNormaliser.normalisedAIOutput(Self.fallbackNewSpec(prompt: trimmed))
                return WidgetSpecAIGenerationResult(spec: spec, usedModel: false, note: "Generation failed — used deterministic template.")
            }

        case .unavailable:
            let spec = WidgetSpecNormaliser.normalisedAIOutput(Self.fallbackNewSpec(prompt: trimmed))
            return WidgetSpecAIGenerationResult(spec: spec, usedModel: false, note: "Apple Intelligence unavailable — used deterministic template.")
        }
    }

    func applyPatch(to spec: WidgetSpec, instruction: String) async -> WidgetSpecAIGenerationResult {
        let trimmedInstruction = Self.clean(instruction, maxLength: 220, fallback: "")
        guard !trimmedInstruction.isEmpty else {
            let s = spec.normalised()
            return WidgetSpecAIGenerationResult(spec: s, usedModel: false, note: "Empty patch instruction — no change.")
        }

        let base = spec.normalised()

        guard WidgetWeaverFeatureFlags.aiEnabled else {
            return WidgetSpecAIGenerationResult(
                spec: base,
                usedModel: false,
                note: "AI disabled — no change."
            )
        }

        switch model.availability {
        case .available:
            do {
                let response = try await session.respond(
                    to: Self.patchPrompt(baseSpec: base, instruction: trimmedInstruction),
                    generating: WidgetSpecPatchPayload.self
                )
                let payload = response.content
                var patched = Self.apply(payload: payload, to: base); if WidgetWeaverFeatureFlags.aiReviewUIEnabled { let lower = trimmedInstruction.lowercased(); if lower.contains("padding") || lower.contains("inset") || lower.contains("radius") || lower.contains("round") || lower.contains("spacing") || lower.contains("gap") || lower.contains("gutter") { let forced = Self.fallbackPatch(base: patched, instruction: trimmedInstruction); patched.style.padding = forced.style.padding; patched.style.cornerRadius = forced.style.cornerRadius; patched.layout.spacing = forced.layout.spacing } }
                return WidgetSpecAIGenerationResult(spec: WidgetSpecNormaliser.normalisedAIOutput(patched), usedModel: true, note: "Applied patch.")
            } catch {
                #if DEBUG
                print("AI Patch fell back despite Apple Intelligence: Ready. Underlying error: \(error)")
                #endif

                let patched = WidgetSpecNormaliser.normalisedAIOutput(Self.fallbackPatch(base: base, instruction: trimmedInstruction))
                return WidgetSpecAIGenerationResult(spec: patched, usedModel: false, note: WidgetWeaverFeatureFlags.aiReviewUIEnabled ? "Applied patch using deterministic rules.\nModel patch failed (\(Self.clean("\(type(of: error)): \(error.localizedDescription)", maxLength: 140, fallback: String(describing: type(of: error)))))." : "Applied patch using deterministic rules.")
            }

        case .unavailable:
            let patched = WidgetSpecNormaliser.normalisedAIOutput(Self.fallbackPatch(base: base, instruction: trimmedInstruction))
            return WidgetSpecAIGenerationResult(spec: patched, usedModel: false, note: "Apple Intelligence unavailable — used deterministic rules.")
        }
    }
}

// MARK: - Prompt building

private extension WidgetSpecAIService {
    static func newSpecPrompt(userPrompt: String) -> String {
        """
        Create a WidgetWeaver widget design. Output only a WidgetSpecGenerationPayload.
        Keep it simple and readable for WidgetKit. Text should be short and glanceable.
        Brief: \(userPrompt)
        """
    }

    static func patchPrompt(baseSpec: WidgetSpec, instruction: String) -> String {
        let summary = specSummary(baseSpec)
        return """
        Update the existing WidgetWeaver design using the edit instruction.
        Current design: \(summary)
        Edit instruction: \(instruction)
        Output only a WidgetSpecPatchPayload containing just the changes:
        - Omit unchanged fields; do not output null/nil for unchanged values.
        - Use removeSecondaryText/removeSymbol/removeImage when the instruction asks for removal.
        """
    }

    static func specSummary(_ spec: WidgetSpec) -> String {
        let s = spec.normalised()

        let symbolSummary: String = {
            guard let sym = s.symbol else { return "none" }
            return "\(sym.name), placement=\(sym.placement.rawValue), size=\(Int(sym.size)), weight=\(sym.weight.rawValue), rendering=\(sym.renderingMode.rawValue), tint=\(sym.tint.rawValue)"
        }()

        let imageSummary: String = {
            guard let img = s.image else { return "none" }
            return "present (contentMode=\(img.contentMode.rawValue), height=\(Int(img.height)), cornerRadius=\(Int(img.cornerRadius)))"
        }()

        return """
        name: \(s.name)
        primaryText: \(s.primaryText)
        secondaryText: \(s.secondaryText ?? "none")
        symbol: \(symbolSummary)
        image: \(imageSummary)
        layout: axis=\(s.layout.axis.rawValue), alignment=\(s.layout.alignment.rawValue), spacing=\(Int(s.layout.spacing)), primaryLineLimitSmall=\(s.layout.primaryLineLimitSmall), primaryLineLimit=\(s.layout.primaryLineLimit), secondaryLineLimit=\(s.layout.secondaryLineLimit)
        style: background=\(s.style.background.rawValue), accent=\(s.style.accent.rawValue), padding=\(Int(s.style.padding)), cornerRadius=\(Int(s.style.cornerRadius)), primaryTextStyle=\(s.style.primaryTextStyle.rawValue), secondaryTextStyle=\(s.style.secondaryTextStyle.rawValue)
        """
    }
}

// MARK: - Mapping to WidgetSpec

private extension WidgetSpecAIService {
    static func normalisedAlignmentRawValue(_ rawValue: String) -> String {
        let trimmed = collapseWhitespace(rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        switch lower {
        case "center", "centre":
            return LayoutAlignmentToken.centre.rawValue
        default:
            return trimmed
        }
    }

    static func widgetSpec(from payload: WidgetSpecGenerationPayload) -> WidgetSpec {
        let name = clean(payload.name, maxLength: 24, fallback: "WidgetWeaver")
        let primary = clean(payload.primaryText, maxLength: 46, fallback: "Hello")
        let secondary = optionalClean(payload.secondaryText, maxLength: 60)

        let axis = LayoutAxisToken(rawValue: payload.axis) ?? .vertical
        let alignmentRaw = normalisedAlignmentRawValue(payload.alignment)
        let alignment = LayoutAlignmentToken(rawValue: alignmentRaw) ?? .leading

        var layout = LayoutSpec.defaultLayout
        layout.axis = axis
        layout.alignment = alignment
        layout.spacing = payload.spacing

        let background = BackgroundToken(rawValue: payload.background) ?? .accentGlow
        let accent = AccentToken(rawValue: payload.accent) ?? .blue

        let primaryStyle = TextStyleToken(rawValue: payload.primaryTextStyle) ?? .automatic
        let secondaryStyle = TextStyleToken(rawValue: payload.secondaryTextStyle) ?? .automatic

        var style = StyleSpec.defaultStyle
        style.padding = payload.padding
        style.cornerRadius = payload.cornerRadius
        style.background = background
        style.accent = accent
        style.primaryTextStyle = primaryStyle
        style.secondaryTextStyle = secondaryStyle
        style.nameTextStyle = .automatic

        let symbol: SymbolSpec? = {
            guard let symName = optionalClean(payload.symbolName, maxLength: 80), !symName.isEmpty else { return nil }
            let placement = SymbolPlacementToken(rawValue: payload.symbolPlacement ?? "") ?? .beforeName
            let weight = SymbolWeightToken(rawValue: payload.symbolWeight ?? "") ?? .semibold
            let rendering = SymbolRenderingModeToken(rawValue: payload.symbolRenderingMode ?? "") ?? .hierarchical
            let tint = SymbolTintToken(rawValue: payload.symbolTint ?? "") ?? .accent

            return SymbolSpec(
                name: symName,
                size: payload.symbolSize ?? 18,
                weight: weight,
                renderingMode: rendering,
                tint: tint,
                placement: placement
            )
        }()

        return WidgetSpec(
            version: WidgetSpec.currentVersion,
            id: UUID(),
            name: name,
            primaryText: primary,
            secondaryText: secondary,
            updatedAt: Date(),
            symbol: symbol,
            image: nil,
            layout: layout,
            style: style
        )
    }

    static func apply(payload: WidgetSpecPatchPayload, to base: WidgetSpec) -> WidgetSpec {
        var s = base.normalised()

        if let name = payload.name { s.name = clean(name, maxLength: 24, fallback: s.name) }
        if let primary = payload.primaryText { s.primaryText = clean(primary, maxLength: 46, fallback: s.primaryText) }

        if payload.removeSecondaryText == true {
            s.secondaryText = nil
        } else if let secondary = payload.secondaryText {
            s.secondaryText = optionalClean(secondary, maxLength: 60)
        }

        if payload.removeImage == true { s.image = nil }

        // Layout edits
        var layout = s.layout
        if let axisRaw = payload.axis, let axis = LayoutAxisToken(rawValue: axisRaw) { layout.axis = axis }
        if let alignmentRaw = payload.alignment, let align = LayoutAlignmentToken(rawValue: normalisedAlignmentRawValue(alignmentRaw)) { layout.alignment = align }
        if let spacing = payload.spacing { layout.spacing = spacing }
        if let v = payload.primaryLineLimitSmall { layout.primaryLineLimitSmall = v }
        if let v = payload.primaryLineLimit { layout.primaryLineLimit = v }
        if let v = payload.secondaryLineLimit { layout.secondaryLineLimit = v }
        s.layout = layout

        // Style edits
        var style = s.style
        if let padding = payload.padding { style.padding = padding }
        if let radius = payload.cornerRadius { style.cornerRadius = radius }
        if let bgRaw = payload.background, let bg = BackgroundToken(rawValue: bgRaw) { style.background = bg }
        if let accentRaw = payload.accent, let ac = AccentToken(rawValue: accentRaw) { style.accent = ac }
        if let ptRaw = payload.primaryTextStyle, let pt = TextStyleToken(rawValue: ptRaw) { style.primaryTextStyle = pt }
        if let stRaw = payload.secondaryTextStyle, let st = TextStyleToken(rawValue: stRaw) { style.secondaryTextStyle = st }
        s.style = style

        // Symbol edits
        if payload.removeSymbol == true {
            s.symbol = nil
        } else {
            let anySymbolField =
                payload.symbolName != nil ||
                payload.symbolPlacement != nil ||
                payload.symbolSize != nil ||
                payload.symbolWeight != nil ||
                payload.symbolRenderingMode != nil ||
                payload.symbolTint != nil

            if anySymbolField {
                var sym = s.symbol ?? SymbolSpec(name: "sparkles")

                if let symName = optionalClean(payload.symbolName, maxLength: 80), !symName.isEmpty { sym.name = symName }
                if let placementRaw = payload.symbolPlacement, let placement = SymbolPlacementToken(rawValue: placementRaw) { sym.placement = placement }
                if let size = payload.symbolSize { sym.size = size }
                if let weightRaw = payload.symbolWeight, let weight = SymbolWeightToken(rawValue: weightRaw) { sym.weight = weight }
                if let modeRaw = payload.symbolRenderingMode, let mode = SymbolRenderingModeToken(rawValue: modeRaw) { sym.renderingMode = mode }
                if let tintRaw = payload.symbolTint, let tint = SymbolTintToken(rawValue: tintRaw) { sym.tint = tint }

                s.symbol = sym
            }
        }

        s.updatedAt = Date()
        return s
    }
}

// MARK: - Deterministic fallback rules

private extension WidgetSpecAIService {
    static func fallbackNewSpec(prompt: String) -> WidgetSpec {
        let trimmed = clean(prompt, maxLength: 280, fallback: "WidgetWeaver")
        let lower = trimmed.lowercased()

        let accent = detectAccent(in: lower) ?? .blue

        var background: BackgroundToken = .accentGlow
        if lower.contains("subtlematerial") || lower.contains("subtle material") || lower.contains("material") || lower.contains("frosted") || lower.contains("blur") {
            background = .subtleMaterial
        }
        if lower.contains("radialglow") || lower.contains("radial glow") || lower.contains("radial") {
            background = .radialGlow
        }
        if lower.contains("solidaccent") || lower.contains("solid accent") || lower.contains("tinted") {
            background = .solidAccent
        }
        if containsWord(lower, word: "plain") || lower.contains("minimal") || lower.contains("clean") || lower.contains("simple") {
            background = .plain
        }
        if lower.contains("accentglow") || lower.contains("accent glow") || lower.contains("bold") || lower.contains("vibrant") || lower.contains("glow") {
            background = .accentGlow
        }
        if lower.contains("transparent") || lower.contains("clear background") {
            background = .plain
        }

        if containsWord(lower, word: "aurora") { background = .aurora }
        if containsWord(lower, word: "sunset") { background = .sunset }
        if containsWord(lower, word: "midnight") { background = .midnight }
        if containsWord(lower, word: "candy") { background = .candy }

        let axis: LayoutAxisToken = (lower.contains("horizontal") || lower.contains("row")) ? .horizontal : .vertical

        let alignment: LayoutAlignmentToken = {
            if lower.contains("trailing") || lower.contains("right") { return .trailing }
            if lower.contains("center") || lower.contains("centre") { return .center }
            return .leading
        }()

        var spacing: Double = 6
        if lower.contains("compact") || lower.contains("tight") { spacing = 4 }
        if lower.contains("spacious") || lower.contains("airy") { spacing = 10 }

        let texts = fallbackTexts(from: trimmed)

        let wantsSymbol: Bool = !(lower.contains("no icon") || lower.contains("no symbol") || lower.contains("without icon"))

        var style = StyleSpec.defaultStyle
        style.background = background
        style.accent = accent
        style.primaryTextStyle = (lower.contains("big title") || lower.contains("bigger title") || lower.contains("large title")) ? .title2 : .headline
        style.secondaryTextStyle = .caption2
        style.nameTextStyle = .caption
        if lower.contains("minimal") { style.padding = 10 }

        var layout = LayoutSpec.defaultLayout
        layout.axis = axis
        layout.alignment = alignment
        layout.spacing = spacing

        let symbol = wantsSymbol ? fallbackSymbol(for: lower, accentPreferred: true) : nil

        return WidgetSpec(
            version: WidgetSpec.currentVersion,
            id: UUID(),
            name: texts.name,
            primaryText: texts.primary,
            secondaryText: texts.secondary,
            updatedAt: Date(),
            symbol: symbol,
            image: nil,
            layout: layout,
            style: style
        )
    }

    static func fallbackPatch(base: WidgetSpec, instruction: String) -> WidgetSpec {
        var s = base.normalised()
        let lower = instruction.lowercased()
        let collapsedLower = collapseWhitespace(lower).trimmingCharacters(in: .whitespacesAndNewlines)
        let mentionsBackground = lower.contains("background") || containsWord(lower, word: "bg")

        if let ac = detectAccent(in: lower) { s.style.accent = ac }

        if lower.contains("radialglow") || lower.contains("radial glow") || lower.contains("radial") { s.style.background = .radialGlow }
        if lower.contains("solidaccent") || lower.contains("solid accent") || lower.contains("tinted") { s.style.background = .solidAccent }
        if lower.contains("accentglow") || lower.contains("accent glow") || lower.contains("glow") { s.style.background = .accentGlow }
        if containsWord(lower, word: "plain") || lower.contains("clean") || lower.contains("simple") { s.style.background = .plain }

        if lower.contains("minimal") || lower.contains("more minimal") || lower.contains("make it minimal") || lower.contains("simplify") {
            s.style.background = .plain
            s.style.padding = min(s.style.padding, 12)
            s.layout.spacing = min(s.layout.spacing, 6)
            s.style.primaryTextStyle = .headline
            s.style.secondaryTextStyle = .caption2

            if var sym = s.symbol {
                sym.renderingMode = .monochrome
                sym.tint = .primary
                sym.size = min(sym.size, 16)
                s.symbol = sym
            }
        }

        if lower.contains("bigger title") || lower.contains("larger title") || lower.contains("make title bigger") || lower.contains("bigger primary") {
            s.style.primaryTextStyle = .title2
        }
        if lower.contains("smaller title") || lower.contains("make title smaller") {
            s.style.primaryTextStyle = .headline
        }

        if lower.contains("transparent") || lower.contains("clear background") { s.style.background = .plain }
        if collapsedLower == "plain" || (mentionsBackground && containsWord(lower, word: "plain")) { s.style.background = .plain }

        if lower.contains("subtlematerial") || lower.contains("subtle material") || (mentionsBackground && (lower.contains("material") || lower.contains("frosted") || lower.contains("blur"))) {
            s.style.background = .subtleMaterial
        }
        if lower.contains("accentglow") || lower.contains("accent glow") || lower.contains("accent background") || lower.contains("use accent as background") {
            s.style.background = .accentGlow
        }

        if containsWord(lower, word: "aurora") { s.style.background = .aurora }
        if containsWord(lower, word: "sunset") { s.style.background = .sunset }
        if containsWord(lower, word: "midnight") { s.style.background = .midnight }
        if containsWord(lower, word: "candy") { s.style.background = .candy }

        if lower.contains("horizontal") { s.layout.axis = .horizontal }
        if lower.contains("vertical") { s.layout.axis = .vertical }
        if lower.contains("center") || lower.contains("centre") { s.layout.alignment = .center }

        if lower.contains("more spacing") || lower.contains("increase spacing") { s.layout.spacing += 2 }
        if lower.contains("less spacing") || lower.contains("decrease spacing") { s.layout.spacing -= 2 }

        if lower.contains("remove secondary") || lower.contains("no secondary") || lower.contains("no subtitle") || lower.contains("remove subtitle") {
            s.secondaryText = nil
        }

        if lower.contains("remove symbol") || lower.contains("remove icon") || lower.contains("no symbol") || lower.contains("no icon") {
            s.symbol = nil
        }

        if lower.contains("remove image") || lower.contains("no image") {
            s.image = nil
        }

        if lower.contains("more padding") || lower.contains("increase padding") { s.style.padding += 2 }
        if lower.contains("less padding") || lower.contains("decrease padding") { s.style.padding -= 2 }

        if lower.contains("more rounded") || lower.contains("rounder") { s.style.cornerRadius += 4 }
        if lower.contains("less rounded") || lower.contains("sharper") { s.style.cornerRadius -= 4 }

        let hardenedSimplePromptParsing = WidgetWeaverFeatureFlags.aiReviewUIEnabled
        let paddingPattern = "(?:\\bpadding\\b|\\bpad\\b)\\s*(?:to\\s*)?(?:=|:)?\\s*([0-9]+(?:\\.[0-9]+)?)"
        let cornerRadiusPattern = "(?:\\bcorner(?:\\s*radius|[-_]?radius)?\\b|\\bcornerradius\\b|\\bradius\\b)\\s*(?:to\\s*)?(?:=|:)?\\s*([0-9]+(?:\\.[0-9]+)?)"
        let spacingPattern = "(?:\\bspacing\\b|\\bgap\\b|\\bspace\\b)\\s*(?:to\\s*)?(?:=|:)?\\s*([0-9]+(?:\\.[0-9]+)?)"
        let fragments: [String] = {
            guard hardenedSimplePromptParsing else { return [collapsedLower] }
            let splitReady = lower.replacingOccurrences(of: "\n", with: ",").replacingOccurrences(of: "\r", with: ",")
            return collapseWhitespace(splitReady).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " and ", with: ",").split(separator: ",").map(String.init)
        }()
        for rawFragment in fragments {
            var fragment = collapseWhitespace(rawFragment).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fragment.isEmpty else { continue }
            if hardenedSimplePromptParsing {
                fragment = fragment.replacingOccurrences(of: "\\b(inset|insets)\\b", with: "padding", options: .regularExpression).replacingOccurrences(of: "\\b(gap|gutter)\\b", with: "spacing", options: .regularExpression).replacingOccurrences(of: "\\brounded\\s+corners?\\b", with: "radius", options: .regularExpression).replacingOccurrences(of: "\\brounding\\b", with: "radius", options: .regularExpression)
            }
            if let v = firstDoubleMatch(paddingPattern, in: fragment) { s.style.padding = v }
            if let v = firstDoubleMatch(cornerRadiusPattern, in: fragment) { s.style.cornerRadius = v }
            if let v = firstDoubleMatch(spacingPattern, in: fragment) { s.layout.spacing = v }
        }

        s.updatedAt = Date()
        return s
    }
}

// MARK: - Small text helpers

private extension WidgetSpecAIService {
    struct FallbackTexts {
        let name: String
        let primary: String
        let secondary: String?
    }

    static func containsWord(_ text: String, word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func firstDoubleMatch(_ pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let numRange = Range(match.range(at: 1), in: text)
        else { return nil }

        return Double(text[numRange])
    }

    static func fallbackTexts(from prompt: String) -> FallbackTexts {
        let collapsed = collapseWhitespace(prompt)
        let words = collapsed.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        let nameRaw = words.prefix(2).joined(separator: " ")
        let primaryRaw = words.prefix(6).joined(separator: " ")

        let name = clean(titleCase(nameRaw), maxLength: 24, fallback: "WidgetWeaver")
        let primary = clean(primaryRaw, maxLength: 46, fallback: "Hello")

        let remainder = words.dropFirst(6)
        let secondaryRaw = remainder.prefix(8).joined(separator: " ")
        let secondary = optionalClean(secondaryRaw, maxLength: 60)

        return FallbackTexts(name: name, primary: primary, secondary: secondary)
    }

    static func fallbackSymbol(for lowerPrompt: String, accentPreferred: Bool) -> SymbolSpec? {
        let symbolName: String = {
            if lowerPrompt.contains("weather") { return "cloud.sun.fill" }
            if lowerPrompt.contains("finance") || lowerPrompt.contains("stocks") || lowerPrompt.contains("price") { return "chart.line.uptrend.xyaxis" }
            if lowerPrompt.contains("todo") || lowerPrompt.contains("task") { return "checkmark.circle.fill" }
            if lowerPrompt.contains("habit") { return "repeat.circle.fill" }
            if lowerPrompt.contains("time") || lowerPrompt.contains("clock") { return "clock.fill" }
            if lowerPrompt.contains("music") { return "music.note" }
            if lowerPrompt.contains("fitness") || lowerPrompt.contains("workout") { return "figure.run" }
            if lowerPrompt.contains("notes") { return "note.text" }
            if lowerPrompt.contains("calendar") { return "calendar" }
            if lowerPrompt.contains("minimal") || lowerPrompt.contains("clean") { return "" }
            return "sparkles"
        }()

        let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return SymbolSpec(
            name: trimmed,
            size: 18,
            weight: .semibold,
            renderingMode: accentPreferred ? .hierarchical : .monochrome,
            tint: accentPreferred ? .accent : .primary,
            placement: .beforeName
        )
    }

    static func detectAccent(in lowerText: String) -> AccentToken? {
        if lowerText.contains("indigo") { return .indigo }
        if lowerText.contains("yellow") || lowerText.contains("gold") { return .yellow }

        if lowerText.contains("teal") || lowerText.contains("mint") { return .teal }
        if lowerText.contains("green") { return .green }
        if lowerText.contains("orange") { return .orange }
        if lowerText.contains("red") { return .red }
        if lowerText.contains("pink") { return .pink }
        if lowerText.contains("purple") { return .purple }
        if lowerText.contains("gray") || lowerText.contains("grey") { return .gray }
        if lowerText.contains("blue") { return .blue }

        if lowerText.contains("brown") { return .orange }
        if lowerText.contains("indigo") { return .indigo }

        return nil
    }

    static func clean(_ text: String, maxLength: Int, fallback: String) -> String {
        let collapsed = collapseWhitespace(text)
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty { return fallback }
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength))
    }

    static func optionalClean(_ text: String?, maxLength: Int) -> String? {
        guard let text else { return nil }
        let c = clean(text, maxLength: maxLength, fallback: "")
        return c.isEmpty ? nil : c
    }

    static func collapseWhitespace(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)

        var lastWasSpace = false
        for ch in text {
            if ch.isWhitespace {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out
    }

    static func titleCase(_ raw: String) -> String {
        raw.split(separator: " ").map { part in
            let p = String(part)
            guard let first = p.first else { return p }
            return first.uppercased() + p.dropFirst()
        }.joined(separator: " ")
    }
}
