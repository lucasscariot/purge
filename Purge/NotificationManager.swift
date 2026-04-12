import UserNotifications
import SwiftUI

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    override init() {
        super.init()
        print("NotificationManager: Initializing and setting delegate")
        UNUserNotificationCenter.current().delegate = self
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        print("NotificationManager: Foreground notification received: \(notification.request.content.title)")
        
        // Use .banner and .alert, .sound, .badge to ensure visibility
        completionHandler([.banner, .alert, .sound, .badge])
    }
}
