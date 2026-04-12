import Foundation

let date = Date()
let currentMonth = Calendar.current.component(.month, from: date)
let currentDay = Calendar.current.component(.day, from: date)
print("Month: \(currentMonth), Day: \(currentDay)")
