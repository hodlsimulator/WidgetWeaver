//
//  WidgetSpec+Utilities.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Utilities

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}

extension Double {
    func normalised() -> Double { isFinite ? self : 0 }
}

// MARK: - Variables (App Group)
//
// Variable references inside text fields:
//
// - "{{key}}" -> replaced with the current value for "key"
// - "{{key|fallback}}" -> fallback used when key is missing/empty
//
// Extended (filters):
// - "{{key|fallback|upper}}"
// - "{{amount|0|number:0}}"
// - "{{progress|0|bar:10}}"
// - "{{last_done|Never|relative}}"
// - "{{__now||date:HH:mm}}"
//
// Inline maths:
// - "{{=streak+1|0}}"
// - "{{=done/total*100|0|number:0}}"
//
// Keys are canonicalised as:
// - trimmed
// - lowercased
// - internal whitespace collapsed to single spaces

public final class WidgetWeaverVariableStore: @unchecked Sendable {
    public static let shared = WidgetWeaverVariableStore()

    private let defaults: UserDefaults
    private let variablesKey = "widgetweaver.variables.v1"

    public init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
    }

    public func loadAll() -> [String: String] {
        guard WidgetWeaverEntitlements.isProUnlocked else { return [:] }
        return loadAllInternal()
    }

    public func value(for rawKey: String) -> String? {
        guard WidgetWeaverEntitlements.isProUnlocked else { return nil }
        let key = Self.canonicalKey(rawKey)
        guard !key.isEmpty else { return nil }
        let vars = loadAllInternal()
        return vars[key]
    }

    public func setValue(_ value: String, for rawKey: String) {
        guard WidgetWeaverEntitlements.isProUnlocked else { return }
        let key = Self.canonicalKey(rawKey)
        guard !key.isEmpty else { return }

        var vars = loadAllInternal()
        vars[key] = value
        saveAllInternal(vars)
        flushAndNotifyWidgets()
    }

    public func removeValue(for rawKey: String) {
        guard WidgetWeaverEntitlements.isProUnlocked else { return }
        let key = Self.canonicalKey(rawKey)
        guard !key.isEmpty else { return }

        var vars = loadAllInternal()
        vars.removeValue(forKey: key)
        saveAllInternal(vars)
        flushAndNotifyWidgets()
    }

    public func clearAll() {
        guard WidgetWeaverEntitlements.isProUnlocked else { return }
        defaults.removeObject(forKey: variablesKey)
        flushAndNotifyWidgets()
    }

    public static func canonicalKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var out = ""
        out.reserveCapacity(min(trimmed.count, 64))

        var lastWasSpace = false
        for ch in trimmed.lowercased() {
            if ch.isWhitespace {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.append(ch)
                lastWasSpace = false
            }

            if out.count >= 64 { break }
        }

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadAllInternal() -> [String: String] {
        guard let data = defaults.data(forKey: variablesKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            return [:]
        }
    }

    private func saveAllInternal(_ vars: [String: String]) {
        do {
            let data = try JSONEncoder().encode(vars)
            defaults.set(data, forKey: variablesKey)
        } catch {
            // Intentionally ignored.
        }
    }

    private func flushAndNotifyWidgets() {
        defaults.synchronize()

        #if canImport(WidgetKit)
        let kind = WidgetWeaverWidgetKinds.main
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 17.0, *) {
                WidgetCenter.shared.invalidateConfigurationRecommendations()
            }
        }
        #endif
    }
}

// MARK: - Variable template rendering

public enum WidgetWeaverVariableTemplate {

    // Built-in keys (always available, no stored variable needed):
    // - __now        -> ISO8601 UTC (internet date time)
    // - __now_unix   -> seconds since 1970
    // - __today      -> yyyy-MM-dd (local calendar day)
    // - __time       -> HH:mm (local)
    // - __weekday    -> EEE (Mon/Tue/...)
    public static func builtInVariables(now: Date = Date()) -> [String: String] {
        let calendar = Calendar.autoupdatingCurrent
        let startOfDay = calendar.startOfDay(for: now)

        return [
            "__now": iso8601String(now),
            "__now_unix": String(Int64(now.timeIntervalSince1970)),
            "__today": formatDate(startOfDay, format: "yyyy-MM-dd", timeZone: calendar.timeZone),
            "__time": formatDate(now, format: "HH:mm", timeZone: calendar.timeZone),
            "__weekday": formatDate(now, format: "EEE", timeZone: calendar.timeZone),
        ]
    }

    public static func iso8601String(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    public static func render(_ template: String, variables: [String: String]) -> String {
        render(template, variables: variables, now: Date(), maxPasses: 3)
    }

    public static func render(
        _ template: String,
        variables: [String: String],
        now: Date,
        maxPasses: Int
    ) -> String {
        guard template.contains("{{") else { return template }

        var current = template
        var pass = 0

        while pass < maxPasses, current.contains("{{") {
            let next = renderSinglePass(current, variables: variables, now: now)
            if next == current { break }
            current = next
            pass += 1
        }

        return current
    }

    public static func isTimeDependentTemplate(_ template: String) -> Bool {
        guard template.contains("{{") else { return false }
        let s = template.lowercased()

        if s.contains("__now") || s.contains("__today") || s.contains("__time") { return true }
        if s.contains("|relative") { return true }
        if s.contains("|daysuntil") || s.contains("|hoursuntil") || s.contains("|minutesuntil") { return true }
        if s.contains("|sincedays") || s.contains("|sincehours") || s.contains("|sinceminutes") { return true }

        return false
    }

    private static func renderSinglePass(_ template: String, variables: [String: String], now: Date) -> String {
        var out = ""
        out.reserveCapacity(template.count)

        var cursor = template.startIndex
        let end = template.endIndex

        while cursor < end {
            guard let open = template.range(of: "{{", range: cursor..<end) else {
                out.append(contentsOf: template[cursor..<end])
                break
            }

            out.append(contentsOf: template[cursor..<open.lowerBound])

            guard let close = template.range(of: "}}", range: open.upperBound..<end) else {
                out.append(contentsOf: template[open.lowerBound..<end])
                break
            }

            let tokenBody = String(template[open.upperBound..<close.lowerBound])
            out.append(resolveToken(tokenBody, variables: variables, now: now))

            cursor = close.upperBound
        }

        return out
    }

    private struct ParsedToken {
        let rawBase: String
        let fallback: String
        let filters: [String]
    }

    private static func resolveToken(_ rawToken: String, variables: [String: String], now: Date) -> String {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "" }

        let parsed = parseToken(token)

        // Base value
        var value: String
        let base = parsed.rawBase.trimmingCharacters(in: .whitespacesAndNewlines)

        if base.hasPrefix("=") {
            let expr = String(base.dropFirst())
            if let d = WidgetWeaverExpression.evaluate(expr, variables: variables, now: now) {
                value = compactNumberString(d)
            } else {
                value = parsed.fallback
            }
        } else {
            let key = WidgetWeaverVariableStore.canonicalKey(base)
            if !key.isEmpty, let v = variables[key], !v.isEmpty {
                value = v
            } else {
                value = parsed.fallback
            }
        }

        // Filters
        for f in parsed.filters {
            value = applyFilter(f, to: value, variables: variables, now: now)
        }

        return value
    }

    // Parsing strategy:
    //
    // 1) Explicit filter delimiter "||" (unambiguous):
    //    "{{key|fallback||upper|number:0}}"
    //
    // 2) Otherwise:
    //    - "{{key|fallback}}" -> fallback only
    //    - "{{key|fallback|upper}}" -> filters only if recognised
    //    - If pipes exist but no recognised filters, treat everything after first pipe as fallback (legacy-friendly).
    private static func parseToken(_ token: String) -> ParsedToken {
        if let range = token.range(of: "||") {
            let left = String(token[..<range.lowerBound])
            let right = String(token[range.upperBound...])

            let (base, fallback) = splitBaseAndFallback(left)
            let filters = right
                .split(separator: "|", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return ParsedToken(rawBase: base, fallback: fallback, filters: filters)
        }

        let parts = token.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
        if parts.count <= 1 {
            return ParsedToken(rawBase: token, fallback: "", filters: [])
        }

        if parts.count == 2 {
            return ParsedToken(
                rawBase: parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                fallback: parts[1],
                filters: []
            )
        }

        // 3+ parts: only treat as filter pipeline if any post-fallback segment looks like a supported filter.
        let postFallback = parts.dropFirst(2)
        let hasRecognisedFilter = postFallback.contains { looksLikeSupportedFilter($0) }

        if hasRecognisedFilter {
            return ParsedToken(
                rawBase: parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                fallback: parts[1],
                filters: postFallback.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            )
        } else {
            let base = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = parts.dropFirst().joined(separator: "|")
            return ParsedToken(rawBase: base, fallback: fallback, filters: [])
        }
    }

    private static func splitBaseAndFallback(_ s: String) -> (String, String) {
        guard let pipe = s.firstIndex(of: "|") else {
            return (s.trimmingCharacters(in: .whitespacesAndNewlines), "")
        }
        let base = String(s[..<pipe]).trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(s[s.index(after: pipe)...])
        return (base, fallback)
    }

    private static func looksLikeSupportedFilter(_ filter: String) -> Bool {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let name = filterName(trimmed)
        switch name {
        case "upper", "lower", "title", "trim",
             "prefix", "suffix",
             "pad",
             "number", "percent", "currency",
             "round", "floor", "ceil", "abs", "clamp",
             "date", "relative",
             "daysuntil", "hoursuntil", "minutesuntil",
             "sincedays", "sincehours", "sinceminutes",
             "plural",
             "bar":
            return true
        default:
            return false
        }
    }

    private static func filterName(_ filter: String) -> String {
        if let idx = filter.firstIndex(of: ":") {
            return filter[..<idx].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func filterArgString(_ filter: String) -> String? {
        guard let idx = filter.firstIndex(of: ":") else { return nil }
        return String(filter[filter.index(after: idx)...])
    }

    private static func applyFilter(_ filter: String, to value: String, variables: [String: String], now: Date) -> String {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }

        let name = filterName(trimmed)
        let args = filterArgString(trimmed) ?? ""

        switch name {
        case "upper":
            return value.uppercased()

        case "lower":
            return value.lowercased()

        case "title":
            return value.localizedCapitalized

        case "trim":
            return value.trimmingCharacters(in: .whitespacesAndNewlines)

        case "prefix":
            return args + value

        case "suffix":
            return value + args

        case "pad":
            let n = Int(args.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            guard n > 0 else { return value }
            return leftPadZeros(value, toLength: n)

        case "number":
            let decimals = Int(args.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let d = parseDouble(value) else { return value }
            return formatNumber(d, decimals: decimals)

        case "percent":
            let decimals = Int(args.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let d0 = parseDouble(value) else { return value }
            let d: Double
            if abs(d0) <= 1.0 {
                d = d0 * 100.0
            } else {
                d = d0
            }
            let formatted = formatNumber(d, decimals: decimals)
            return formatted + "%"

        case "currency":
            guard let d = parseDouble(value) else { return value }
            let code = args.trimmingCharacters(in: .whitespacesAndNewlines)
            return formatCurrency(d, currencyCode: code.isEmpty ? nil : code)

        case "round":
            guard let d0 = parseDouble(value) else { return value }
            let decimals = Int(args.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let factor = pow(10.0, Double(decimals.clamped(to: 0...12)))
            let d = (d0 * factor).rounded() / factor
            return (decimals == 0) ? compactNumberString(d) : formatNumber(d, decimals: decimals)

        case "floor":
            guard let d = parseDouble(value) else { return value }
            return compactNumberString(floor(d))

        case "ceil":
            guard let d = parseDouble(value) else { return value }
            return compactNumberString(ceil(d))

        case "abs":
            guard let d = parseDouble(value) else { return value }
            return compactNumberString(abs(d))

        case "clamp":
            // clamp:min:max
            let parts = args.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return value }
            guard let d = parseDouble(value) else { return value }
            let lo = parseDouble(parts[0]) ?? d
            let hi = parseDouble(parts[1]) ?? d
            let clamped = d.clamped(to: min(lo, hi)...max(lo, hi))
            return compactNumberString(clamped)

        case "date":
            let format = args.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let d = parseDate(value, now: now) else { return value }
            if format.isEmpty {
                return formatDate(d, dateStyle: .medium, timeStyle: .none, timeZone: Calendar.autoupdatingCurrent.timeZone)
            }
            return formatDate(d, format: format, timeZone: Calendar.autoupdatingCurrent.timeZone)

        case "relative":
            guard let d = parseDate(value, now: now) else { return value }
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .full
            return f.localizedString(for: d, relativeTo: now)

        case "daysuntil":
            guard let d = parseDate(value, now: now) else { return value }
            return String(intCeilDelta(now: now, target: d, unitSeconds: 86400))

        case "hoursuntil":
            guard let d = parseDate(value, now: now) else { return value }
            return String(intCeilDelta(now: now, target: d, unitSeconds: 3600))

        case "minutesuntil":
            guard let d = parseDate(value, now: now) else { return value }
            return String(intCeilDelta(now: now, target: d, unitSeconds: 60))

        case "sincedays":
            guard let d = parseDate(value, now: now) else { return value }
            return String(intCeilDelta(now: d, target: now, unitSeconds: 86400))

        case "sincehours":
            guard let d = parseDate(value, now: now) else { return value }
            return String(intCeilDelta(now: d, target: now, unitSeconds: 3600))

        case "sinceminutes":
            guard let d = parseDate(value, now: now) else { return value }
            return String(intCeilDelta(now: d, target: now, unitSeconds: 60))

        case "plural":
            // plural:singular:plural
            let parts = args.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return value }
            let singular = parts[0]
            let plural = parts[1]
            let n = Int(parseDouble(value) ?? 0)
            return (abs(n) == 1) ? singular : plural

        case "bar":
            // bar:width
            let width = Int(args.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 10
            guard width > 0 else { return value }
            guard let d0 = parseDouble(value) else { return value }
            let fraction: Double
            if abs(d0) <= 1.0 {
                fraction = d0
            } else {
                fraction = d0 / 100.0
            }
            let clamped = fraction.clamped(to: 0...1)
            let filled = Int((clamped * Double(width)).rounded(.toNearestOrAwayFromZero)).clamped(to: 0...width)
            let empty = (width - filled).clamped(to: 0...width)
            return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)

        default:
            return value
        }
    }

    private static func leftPadZeros(_ s: String, toLength n: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= n { return trimmed }
        return String(repeating: "0", count: n - trimmed.count) + trimmed
    }

    static func parseDouble(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let cleaned = t.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private static func compactNumberString(_ d: Double) -> String {
        guard d.isFinite else { return "0" }

        let r = d.rounded()
        if abs(d - r) < 1e-9 {
            return String(Int64(r))
        }

        let s = String(format: "%.6f", d)
        var out = s
        while out.contains(".") && out.last == "0" { out.removeLast() }
        if out.last == "." { out.removeLast() }
        return out
    }

    private static func formatNumber(_ d: Double, decimals: Int?) -> String {
        let nf = NumberFormatter()
        nf.locale = .autoupdatingCurrent
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = true

        if let decimals {
            let clamped = decimals.clamped(to: 0...12)
            nf.minimumFractionDigits = clamped
            nf.maximumFractionDigits = clamped
        } else {
            // Adaptive: no decimals for integers, else up to 2.
            let r = d.rounded()
            if abs(d - r) < 1e-9 {
                nf.minimumFractionDigits = 0
                nf.maximumFractionDigits = 0
            } else {
                nf.minimumFractionDigits = 0
                nf.maximumFractionDigits = 2
            }
        }

        return nf.string(from: NSNumber(value: d)) ?? compactNumberString(d)
    }

    private static func formatCurrency(_ d: Double, currencyCode: String?) -> String {
        let nf = NumberFormatter()
        nf.locale = .autoupdatingCurrent
        nf.numberStyle = .currency
        if let currencyCode, !currencyCode.isEmpty {
            nf.currencyCode = currencyCode
        }
        return nf.string(from: NSNumber(value: d)) ?? compactNumberString(d)
    }

    private static func parseDate(_ s: String, now: Date) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        let calendar = Calendar.autoupdatingCurrent

        switch lowered {
        case "now":
            return now
        case "today":
            return calendar.startOfDay(for: now)
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        default:
            break
        }

        if let num = parseDouble(trimmed) {
            let seconds: TimeInterval
            if abs(num) > 1e11 {
                seconds = num / 1000.0
            } else {
                seconds = num
            }
            return Date(timeIntervalSince1970: seconds)
        }

        // ISO8601 (with & without fractional seconds)
        do {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: trimmed) { return d }
        }
        do {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: trimmed) { return d }
        }

        // Common fixed formats (local tz)
        let tz = calendar.timeZone
        let posix = Locale(identifier: "en_US_POSIX")

        let patterns = [
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd",
            "yyyy/MM/dd HH:mm",
            "yyyy/MM/dd HH:mm:ss",
        ]

        for p in patterns {
            let df = DateFormatter()
            df.locale = posix
            df.timeZone = tz
            df.dateFormat = p
            if let d = df.date(from: trimmed) { return d }
        }

        // HH:mm -> today at that time (local)
        if let hm = parseHourMinute(trimmed) {
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = hm.hour
            comps.minute = hm.minute
            comps.second = 0
            comps.nanosecond = 0
            return calendar.date(from: comps)
        }

        return nil
    }

    private static func parseHourMinute(_ s: String) -> (hour: Int, minute: Int)? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        guard (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    private static func formatDate(_ date: Date, format: String, timeZone: TimeZone) -> String {
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = timeZone
        df.dateFormat = format
        return df.string(from: date)
    }

    private static func formatDate(_ date: Date, dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style, timeZone: TimeZone) -> String {
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = timeZone
        df.dateStyle = dateStyle
        df.timeStyle = timeStyle
        return df.string(from: date)
    }

    private static func intCeilDelta(now: Date, target: Date, unitSeconds: TimeInterval) -> Int {
        let delta = target.timeIntervalSince(now)
        if delta >= 0 {
            return Int(ceil(delta / unitSeconds))
        } else {
            return Int(floor(delta / unitSeconds))
        }
    }
}

// MARK: - Tiny safe expression evaluator for {{= ... }}

private enum WidgetWeaverExpression {
    static func evaluate(_ expression: String, variables: [String: String], now: Date) -> Double? {
        var lexer = Lexer(expression)
        var parser = Parser(lexer: &lexer, variables: variables, now: now)
        return parser.parseExpression()
    }

    private enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case string(String)

        case plus, minus, star, slash, percent, caret
        case lparen, rparen, comma
        case eof
    }

    private struct Lexer {
        private let chars: [Character]
        private var i: Int = 0

        init(_ s: String) { self.chars = Array(s) }

        mutating func nextToken() -> Token {
            skipWhitespace()
            guard i < chars.count else { return .eof }

            let c = chars[i]

            switch c {
            case "+": i += 1; return .plus
            case "-": i += 1; return .minus
            case "*": i += 1; return .star
            case "/": i += 1; return .slash
            case "%": i += 1; return .percent
            case "^": i += 1; return .caret
            case "(": i += 1; return .lparen
            case ")": i += 1; return .rparen
            case ",": i += 1; return .comma
            case "\"":
                return lexString()
            default:
                if isDigit(c) || c == "." {
                    return lexNumber()
                }
                if isIdentifierStart(c) {
                    return lexIdentifier()
                }
                i += 1
                return nextToken()
            }
        }

        private mutating func skipWhitespace() {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
        }

        private func isDigit(_ c: Character) -> Bool {
            c >= "0" && c <= "9"
        }

        private func isIdentifierStart(_ c: Character) -> Bool {
            (c >= "a" && c <= "z") ||
            (c >= "A" && c <= "Z") ||
            c == "_"
        }

        private func isIdentifierBody(_ c: Character) -> Bool {
            isIdentifierStart(c) || isDigit(c)
        }

        private mutating func lexNumber() -> Token {
            let start = i
            var seenDot = false
            while i < chars.count {
                let c = chars[i]
                if c == "." {
                    if seenDot { break }
                    seenDot = true
                    i += 1
                    continue
                }
                if isDigit(c) {
                    i += 1
                    continue
                }
                break
            }
            let s = String(chars[start..<i]).replacingOccurrences(of: ",", with: "")
            return .number(Double(s) ?? 0)
        }

        private mutating func lexIdentifier() -> Token {
            let start = i
            i += 1
            while i < chars.count, isIdentifierBody(chars[i]) { i += 1 }
            return .identifier(String(chars[start..<i]))
        }

        private mutating func lexString() -> Token {
            // leading quote
            i += 1
            let start = i
            while i < chars.count, chars[i] != "\"" { i += 1 }
            let s = String(chars[start..<min(i, chars.count)])
            if i < chars.count, chars[i] == "\"" { i += 1 }
            return .string(s)
        }
    }

    private struct Parser {
        private var lexer: UnsafeMutablePointer<Lexer>
        private var lookahead: Token

        private let variables: [String: String]
        private let now: Date

        init(lexer: inout Lexer, variables: [String: String], now: Date) {
            self.lexer = .allocate(capacity: 1)
            self.lexer.initialize(to: lexer)
            self.lookahead = self.lexer.pointee.nextToken()
            self.variables = variables
            self.now = now
        }

        mutating func parseExpression() -> Double? {
            return parseAddSub()
        }

        private mutating func parseAddSub() -> Double? {
            guard var lhs = parseMulDiv() else { return nil }
            while lookahead == .plus || lookahead == .minus {
                let op = lookahead
                advance()
                guard let rhs = parseMulDiv() else { return nil }
                if op == .plus { lhs += rhs } else { lhs -= rhs }
            }
            return lhs
        }

        private mutating func parseMulDiv() -> Double? {
            guard var lhs = parsePower() else { return nil }
            while lookahead == .star || lookahead == .slash || lookahead == .percent {
                let op = lookahead
                advance()
                guard let rhs = parsePower() else { return nil }
                switch op {
                case .star: lhs *= rhs
                case .slash: lhs = rhs == 0 ? 0 : (lhs / rhs)
                case .percent: lhs = rhs == 0 ? 0 : lhs.truncatingRemainder(dividingBy: rhs)
                default: break
                }
            }
            return lhs
        }

        private mutating func parsePower() -> Double? {
            guard var lhs = parseUnary() else { return nil }
            if lookahead == .caret {
                advance()
                guard let rhs = parsePower() else { return nil } // right-associative
                lhs = pow(lhs, rhs)
            }
            return lhs
        }

        private mutating func parseUnary() -> Double? {
            if lookahead == .plus {
                advance()
                return parseUnary()
            }
            if lookahead == .minus {
                advance()
                guard let v = parseUnary() else { return nil }
                return -v
            }
            return parsePrimary()
        }

        private mutating func parsePrimary() -> Double? {
            switch lookahead {
            case .number(let d):
                advance()
                return d

            case .identifier(let name):
                advance()
                if lookahead == .lparen {
                    // function call
                    advance() // (
                    let args = parseArgumentList()
                    guard lookahead == .rparen else { return nil }
                    advance() // )
                    return evalFunction(name, args: args)
                } else {
                    return resolveIdentifier(name)
                }

            case .lparen:
                advance()
                let v = parseAddSub()
                guard lookahead == .rparen else { return nil }
                advance()
                return v

            case .string:
                // string literal alone is treated as 0
                advance()
                return 0

            default:
                return nil
            }
        }

        private mutating func parseArgumentList() -> [Token] {
            var out: [Token] = []
            if lookahead == .rparen { return out }

            while true {
                if let exprToken = parseExpressionToken() {
                    out.append(exprToken)
                } else {
                    break
                }

                if lookahead == .comma {
                    advance()
                    continue
                }
                break
            }
            return out
        }

        private mutating func parseExpressionToken() -> Token? {
            // Parse an expression and re-wrap as .number, preserving .string/.identifier for var(...)
            // Special case: accept a single string or identifier as an argument without forcing numeric evaluation.
            switch lookahead {
            case .string(let s):
                advance()
                return .string(s)
            case .identifier(let s):
                // allow identifier arguments (var(keyName))
                advance()
                return .identifier(s)
            default:
                if let v = parseAddSub() {
                    return .number(v)
                }
                return nil
            }
        }

        private mutating func advance() {
            lookahead = lexer.pointee.nextToken()
        }

        private func resolveIdentifier(_ name: String) -> Double {
            let lowered = name.lowercased()
            if lowered == "pi" { return Double.pi }
            if lowered == "e" { return M_E }

            // identifier -> variable key
            // underscore maps to space for convenience (last_done -> last done)
            let rawKey = name.replacingOccurrences(of: "_", with: " ")
            let key = WidgetWeaverVariableStore.canonicalKey(rawKey)
            guard !key.isEmpty else { return 0 }

            let raw = variables[key] ?? ""
            let d = WidgetWeaverVariableTemplate.parseDouble(raw) ?? 0
            return d
        }

        private func evalFunction(_ name: String, args: [Token]) -> Double {
            let n = name.lowercased()

            func num(_ t: Token) -> Double {
                switch t {
                case .number(let d): return d
                case .identifier(let s): return resolveIdentifier(s)
                case .string(let s):
                    let key = WidgetWeaverVariableStore.canonicalKey(s)
                    let raw = variables[key] ?? ""
                    return WidgetWeaverVariableTemplate.parseDouble(raw) ?? 0
                default:
                    return 0
                }
            }

            switch n {
            case "min":
                guard !args.isEmpty else { return 0 }
                return args.map(num).min() ?? 0

            case "max":
                guard !args.isEmpty else { return 0 }
                return args.map(num).max() ?? 0

            case "clamp":
                guard args.count >= 3 else { return 0 }
                let x = num(args[0])
                let lo = num(args[1])
                let hi = num(args[2])
                return x.clamped(to: min(lo, hi)...max(lo, hi))

            case "abs":
                guard args.count >= 1 else { return 0 }
                return Swift.abs(num(args[0]))

            case "floor":
                guard args.count >= 1 else { return 0 }
                return Foundation.floor(num(args[0]))

            case "ceil":
                guard args.count >= 1 else { return 0 }
                return Foundation.ceil(num(args[0]))

            case "round":
                guard args.count >= 1 else { return 0 }
                return Foundation.round(num(args[0]))

            case "pow":
                guard args.count >= 2 else { return 0 }
                return Foundation.pow(num(args[0]), num(args[1]))

            case "sqrt":
                guard args.count >= 1 else { return 0 }
                return Foundation.sqrt(max(0, num(args[0])))

            case "log":
                guard args.count >= 1 else { return 0 }
                let x = num(args[0])
                return x <= 0 ? 0 : Foundation.log(x)

            case "exp":
                guard args.count >= 1 else { return 0 }
                return Foundation.exp(num(args[0]))

            case "var":
                // var("key with spaces") or var(key_name)
                guard args.count >= 1 else { return 0 }
                switch args[0] {
                case .string(let s):
                    let key = WidgetWeaverVariableStore.canonicalKey(s)
                    let raw = variables[key] ?? ""
                    return WidgetWeaverVariableTemplate.parseDouble(raw) ?? 0
                case .identifier(let s):
                    return resolveIdentifier(s)
                case .number(let d):
                    return d
                default:
                    return 0
                }

            case "now":
                // now() -> unix seconds
                return now.timeIntervalSince1970

            default:
                return 0
            }
        }
    }
}

// MARK: - Apply variables to a spec at render time

public extension WidgetSpec {
    func resolvingVariables(using store: WidgetWeaverVariableStore = .shared) -> WidgetSpec {
        // Custom variables are Pro-gated, built-ins are always present.
        var vars: [String: String] = WidgetWeaverEntitlements.isProUnlocked ? store.loadAll() : [:]
        let builtIns = WidgetWeaverVariableTemplate.builtInVariables(now: Date())

        for (k, v) in builtIns where vars[k] == nil {
            vars[k] = v
        }

        // Weather variables behave like built-ins (not Pro-gated).
        // These intentionally override any existing keys to keep the widget truthful.
        let weatherVars = WidgetWeaverWeatherStore.shared.variablesDictionary()
        for (k, v) in weatherVars {
            vars[k] = v
        }

        return resolvingVariables(using: vars)
    }

    func resolvingVariables(using vars: [String: String]) -> WidgetSpec {
        var out = self

        out.name = WidgetWeaverVariableTemplate.render(out.name, variables: vars)
        out.primaryText = WidgetWeaverVariableTemplate.render(out.primaryText, variables: vars)
        out.secondaryText = out.secondaryText.map { WidgetWeaverVariableTemplate.render($0, variables: vars) }

        if let m = out.matchedSet {
            var mm = m

            if let s = mm.small {
                var ss = s
                ss.primaryText = WidgetWeaverVariableTemplate.render(ss.primaryText, variables: vars)
                ss.secondaryText = ss.secondaryText.map { WidgetWeaverVariableTemplate.render($0, variables: vars) }
                mm.small = ss
            }

            if let s = mm.medium {
                var ss = s
                ss.primaryText = WidgetWeaverVariableTemplate.render(ss.primaryText, variables: vars)
                ss.secondaryText = ss.secondaryText.map { WidgetWeaverVariableTemplate.render($0, variables: vars) }
                mm.medium = ss
            }

            if let s = mm.large {
                var ss = s
                ss.primaryText = WidgetWeaverVariableTemplate.render(ss.primaryText, variables: vars)
                ss.secondaryText = ss.secondaryText.map { WidgetWeaverVariableTemplate.render($0, variables: vars) }
                mm.large = ss
            }

            out.matchedSet = mm
        }

        return out
    }

    func usesTimeDependentRendering() -> Bool {
        for t in allTemplateStrings() {
            if WidgetWeaverVariableTemplate.isTimeDependentTemplate(t) {
                return true
            }
        }
        return false
    }
    
    func usesWeatherRendering() -> Bool {
        if layout.template == .weather { return true }

        if let m = matchedSet {
            if m.small?.layout.template == .weather { return true }
            if m.medium?.layout.template == .weather { return true }
            if m.large?.layout.template == .weather { return true }
        }

        for t in allTemplateStrings() {
            if t.localizedCaseInsensitiveContains("__weather") { return true }
            if t.localizedCaseInsensitiveContains("{{weather") { return true }
        }

        return false
    }

    private func allTemplateStrings() -> [String] {
        var out: [String] = []
        out.append(name)
        out.append(primaryText)
        if let secondaryText { out.append(secondaryText) }

        if let m = matchedSet {
            if let v = m.small {
                out.append(v.primaryText)
                if let s = v.secondaryText { out.append(s) }
            }
            if let v = m.medium {
                out.append(v.primaryText)
                if let s = v.secondaryText { out.append(s) }
            }
            if let v = m.large {
                out.append(v.primaryText)
                if let s = v.secondaryText { out.append(s) }
            }
        }

        return out
    }
}
