//
//  ManagerTeamLiveActivityAttributes.swift
//  ProvikartWidget
//
//  Live Activity pro manažera – služby dnes, přehled týmu nebo výkon týmu.
//  Musí zůstat identický s kopií v Provikart.
//

import ActivityKit
import Foundation

enum ManagerLiveActivityKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case todayServices
    case teamOverview
    case performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todayServices: return "Služby dnes"
        case .teamOverview: return "Přehled týmu"
        case .performance: return "Výkon týmu"
        }
    }

    var subtitle: String {
        switch self {
        case .todayServices: return "Kolik služeb tým dnes uzavřel"
        case .teamOverview: return "Docházka a otevřené problémy"
        case .performance: return "Služby za měsíc, graf po dnech a nejlepší obchodník"
        }
    }

    var symbolName: String {
        switch self {
        case .todayServices: return "chart.bar.fill"
        case .teamOverview: return "person.3.fill"
        case .performance: return "chart.line.uptrend.xyaxis"
        }
    }

    var compactTitle: String {
        switch self {
        case .todayServices: return "Dnes"
        case .teamOverview: return "Tým"
        case .performance: return "Výkon"
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
        /// Služby týmu za aktuální měsíc.
        var monthServices: Int
        /// Služby týmu po dnech (nejstarší → dnes), max. 7 hodnot.
        var dailyServices: [Int]
        /// Popisky dnů ke grafu („Po“, „Út“…), stejná délka jako dailyServices.
        var dailyLabels: [String]
        /// Nejlepší obchodník měsíce.
        var topPerformerName: String?
        var topPerformerServices: Int
        /// Název měsíce, např. „Listopad“.
        var monthLabel: String?

        init(
            kind: ManagerLiveActivityKind = .todayServices,
            todayServices: Int = 0,
            openProblems: Int = 0,
            teamSize: Int = 0,
            presentToday: Int = 0,
            latestProblemLabel: String? = nil,
            dayLabel: String? = nil,
            monthServices: Int = 0,
            dailyServices: [Int] = [],
            dailyLabels: [String] = [],
            topPerformerName: String? = nil,
            topPerformerServices: Int = 0,
            monthLabel: String? = nil
        ) {
            self.kind = kind
            self.todayServices = todayServices
            self.openProblems = openProblems
            self.teamSize = teamSize
            self.presentToday = presentToday
            self.latestProblemLabel = latestProblemLabel
            self.dayLabel = dayLabel
            self.monthServices = monthServices
            self.dailyServices = dailyServices
            self.dailyLabels = dailyLabels
            self.topPerformerName = topPerformerName
            self.topPerformerServices = topPerformerServices
            self.monthLabel = monthLabel
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
            monthServices = (try? c.decode(Int.self, forKey: .monthServices)) ?? 0
            dailyServices = (try? c.decode([Int].self, forKey: .dailyServices)) ?? []
            dailyLabels = (try? c.decode([String].self, forKey: .dailyLabels)) ?? []
            topPerformerName = try? c.decodeIfPresent(String.self, forKey: .topPerformerName)
            topPerformerServices = (try? c.decode(Int.self, forKey: .topPerformerServices)) ?? 0
            monthLabel = try? c.decodeIfPresent(String.self, forKey: .monthLabel)
        }
    }
}
