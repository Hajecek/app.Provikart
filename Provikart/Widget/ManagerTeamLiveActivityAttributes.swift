//
//  ManagerTeamLiveActivityAttributes.swift
//  Provikart
//
//  Live Activity pro manažera – dnešní služby týmu nebo přehled docházky a problémů.
//  Musí zůstat identický s kopií v ProvikartWidget.
//

import ActivityKit
import Foundation

enum ManagerLiveActivityKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case todayServices
    case teamOverview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todayServices: return "Služby dnes"
        case .teamOverview: return "Přehled týmu"
        }
    }

    var subtitle: String {
        switch self {
        case .todayServices: return "Kolik služeb tým dnes uzavřel"
        case .teamOverview: return "Docházka a otevřené problémy"
        }
    }

    var symbolName: String {
        switch self {
        case .todayServices: return "chart.bar.fill"
        case .teamOverview: return "person.3.fill"
        }
    }

    var compactTitle: String {
        switch self {
        case .todayServices: return "Dnes"
        case .teamOverview: return "Tým"
        }
    }
}

struct ManagerTeamLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var kind: ManagerLiveActivityKind
        var todayServices: Int
        var openProblems: Int
        var teamSize: Int
        var presentToday: Int
        var latestProblemLabel: String?
        var dayLabel: String?

        init(
            kind: ManagerLiveActivityKind = .todayServices,
            todayServices: Int = 0,
            openProblems: Int = 0,
            teamSize: Int = 0,
            presentToday: Int = 0,
            latestProblemLabel: String? = nil,
            dayLabel: String? = nil
        ) {
            self.kind = kind
            self.todayServices = todayServices
            self.openProblems = openProblems
            self.teamSize = teamSize
            self.presentToday = presentToday
            self.latestProblemLabel = latestProblemLabel
            self.dayLabel = dayLabel
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = (try? c.decode(ManagerLiveActivityKind.self, forKey: .kind)) ?? .teamOverview
            todayServices = (try? c.decode(Int.self, forKey: .todayServices)) ?? 0
            openProblems = (try? c.decode(Int.self, forKey: .openProblems)) ?? 0
            teamSize = (try? c.decode(Int.self, forKey: .teamSize)) ?? 0
            presentToday = (try? c.decode(Int.self, forKey: .presentToday)) ?? 0
            latestProblemLabel = try? c.decodeIfPresent(String.self, forKey: .latestProblemLabel)
            dayLabel = try? c.decodeIfPresent(String.self, forKey: .dayLabel)
        }
    }
}
