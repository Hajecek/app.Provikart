//
//  ManagerTeamLiveActivityAttributes.swift
//  Provikart
//
//  Live Activity pro manažera – přehled problémů týmu a docházky.
//

import ActivityKit
import Foundation

struct ManagerTeamLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var openProblems: Int
        var teamSize: Int
        var presentToday: Int
        var latestProblemLabel: String?
    }
}
