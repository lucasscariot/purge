import Foundation
import UserNotifications
import SwiftUI
import Photos

struct NotificationService {
    static func checkAndScheduleNotifications(for dayGroups: [DayGroup]) {
        let currentMonth = Calendar.current.component(.month, from: Date())
        let currentDay = Calendar.current.component(.day, from: Date())
        let currentYear = Calendar.current.component(.year, from: Date())
        
        let pastDays = dayGroups.filter { group in
            let month = Calendar.current.component(.month, from: group.date)
            let day = Calendar.current.component(.day, from: group.date)
            let year = Calendar.current.component(.year, from: group.date)
            return month == currentMonth && day == currentDay && year < currentYear
        }
        
        if !pastDays.isEmpty {
            scheduleNotification(count: pastDays.count)
        }
    }
    
    private static func scheduleNotification(count: Int) {
        let center = UNUserNotificationCenter.current()
        
        let content = UNMutableNotificationContent()
        content.title = "On This Day"
        content.body = "You have memories from past years to check out!"
        content.sound = .default
        
        var dateComponents = DateComponents()
        dateComponents.hour = 1
        dateComponents.minute = 15
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(identifier: "onThisDay", content: content, trigger: trigger)
        
        center.add(request)
    }
}
