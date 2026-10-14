import Domain
import Foundation
import SusurroUI

/// Turns a record of the history into the row the screen draws. A pure function of the record, the time, and the words in
/// `HistoryCopy`, so it is tested without a screen or a database.
struct HistoryRowMapper: Sendable {
    let calendar: Calendar
    let locale: Locale

    init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
    }

    func row(for record: DictationRecord, now: Date) -> HistoryRowState {
        let status = Self.status(record.status)
        return HistoryRowState(
            id: record.id,
            status: status,
            statusLabel: HistoryCopy.statusLabel(status),
            timestamp: timestamp(of: record.createdAt, now: now),
            detail: detail(of: record),
            text: text(of: record, status: status),
            note: note(of: record),
            actions: actions(of: record)
        )
    }

    static func status(_ status: DictationStatus) -> HistoryRowStatus {
        switch status {
        case .processing: .processing
        case .succeeded: .succeeded
        case .noSpeech: .noSpeech
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }

    // MARK: Pieces

    /// "Today, 14:32", "Yesterday, 18:02", "8 Oct, 09:15", and with the year for an earlier year.
    func timestamp(of date: Date, now: Date) -> String {
        let time = date.formatted(Self.style(time: true, in: self))
        if calendar.isDate(date, inSameDayAs: now) { return "Today, \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday, \(time)"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return "\(date.formatted(Self.style(time: false, yearIncluded: !sameYear, in: self))), \(time)"
    }

    private static func style(time: Bool, yearIncluded: Bool = false, in mapper: HistoryRowMapper) -> Date.FormatStyle {
        var style = Date.FormatStyle(locale: mapper.locale, calendar: mapper.calendar, timeZone: mapper.calendar.timeZone)
        style = time ? style.hour().minute() : style.day().month(.abbreviated)
        if !time && yearIncluded { style = style.year() }
        return style
    }

    /// "12 s", or "1 min 5 s" from a minute on. A recording is never shown as 0 s.
    static func length(_ duration: Duration) -> String {
        let seconds = max(1, Int(duration.components.seconds) + (duration.components.attoseconds > 0 ? 1 : 0))
        guard seconds >= 60 else { return "\(seconds) s" }
        let rest = seconds % 60
        return rest == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(rest) s"
    }

    private func detail(of record: DictationRecord) -> String {
        var parts: [String] = []
        if let appName = record.appName, !appName.isEmpty { parts.append(appName) }
        parts.append(Self.length(record.duration))
        if record.audioExpired { parts.append(HistoryCopy.audioExpiredDetail) }
        return parts.joined(separator: " · ")
    }

    private func text(of record: DictationRecord, status: HistoryRowStatus) -> String {
        if status == .processing { return HistoryCopy.placeholder(for: .processing) }
        let candidates = [record.finalText, record.cleanedText, record.rawText]
        return candidates.compactMap { $0 }.first { !$0.isEmpty } ?? HistoryCopy.placeholder(for: status)
    }

    private func note(of record: DictationRecord) -> String? {
        var notes: [String] = []
        switch record.status {
        case .failed:
            notes.append(HistoryCopy.failure(record.failure))
            if record.hasAudio { notes.append(HistoryCopy.retryHint) }
        case .cancelled:
            notes.append(record.hasAudio ? HistoryCopy.cancelledAudioKept : HistoryCopy.cancelled)
        case .succeeded:
            switch record.delivery {
            case .notInserted: notes.append(HistoryCopy.notInserted)
            case .copiedToClipboard: notes.append(HistoryCopy.leftOnClipboard)
            case .inserted, nil: break
            }
            if record.cleanedText == nil, record.fallbackReason != nil { notes.append(HistoryCopy.cleanupFellBack) }
        case .processing, .noSpeech:
            break
        }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    private func actions(of record: DictationRecord) -> [HistoryRowAction] {
        guard record.status != .processing else { return [] }
        var actions: [HistoryRowAction] = []
        if record.rawText?.isEmpty == false {
            actions.append(HistoryRowAction(kind: .copyRaw, title: HistoryCopy.title(of: .copyRaw)))
        }
        if record.cleanedText?.isEmpty == false {
            actions.append(HistoryRowAction(kind: .copyCleaned, title: HistoryCopy.title(of: .copyCleaned)))
        }
        actions.append(
            HistoryRowAction(
                kind: .retry, title: HistoryCopy.title(of: .retry), unavailableReason: retryUnavailableReason(record)))
        actions.append(HistoryRowAction(kind: .delete, title: HistoryCopy.title(of: .delete)))
        return actions
    }

    private func retryUnavailableReason(_ record: DictationRecord) -> String? {
        if record.audioExpired { return HistoryCopy.retryAudioExpired }
        if record.audioURL == nil { return HistoryCopy.retryNoAudio }
        return nil
    }
}
