import Foundation
import EventKit

/// Creates a Reminders entry due on a return deadline. Kept tiny and isolated
/// so the detail view just awaits a Bool. Uses full-access Reminders (iOS 17+).
enum ReturnReminder {
    enum Outcome { case added, denied, failed }

    static func add(merchant: String, deadline: Date) async -> Outcome {
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else { return .denied }

            let reminder = EKReminder(eventStore: store)
            let dateText = deadline.formatted(date: .abbreviated, time: .omitted)
            reminder.title = "Return \(merchant) by \(dateText)"
            reminder.calendar = store.defaultCalendarForNewReminders()

            let cal = Calendar.current
            reminder.dueDateComponents = cal.dateComponents([.year, .month, .day], from: deadline)
            // Nudge at 9am on the deadline day.
            if let alarmDate = cal.date(bySettingHour: 9, minute: 0, second: 0, of: deadline) {
                reminder.addAlarm(EKAlarm(absoluteDate: alarmDate))
            }

            try store.save(reminder, commit: true)
            return .added
        } catch {
            return .failed
        }
    }
}
