import SwiftUI
import UIKit

enum SlipColor {
    static let background = adaptive(light: 0xF7F7F6, dark: 0x0A0A0A)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let fill = adaptive(light: 0xEFEFED, dark: 0x232326)
    static let separator = adaptive(light: 0xE8E8E6, dark: 0x2C2C2E)
    static let ink = adaptive(light: 0x17171A, dark: 0xF2F2F7)
    static let secondary = adaptive(light: 0x66666E, dark: 0x98989F)
    static let seal = fixed(0xC63A2B)
    static let sealTint = adaptive(light: 0xFAE8E5, dark: 0x3B211E)
    static let win = adaptive(light: 0x1F7A43, dark: 0x67D08F)
    static let ambient = fixed(0x5E5560)
    static let ticket = fixed(0x232126)
    static let onSeal = fixed(0xFFFFFF)
    static let onTicket = fixed(0xF2F2F7)
    static let ticketSecondary = fixed(0xB6B3BB)
    static let clear = Color.clear

    static let artPink = fixed(0xF2BBD5)
    static let artYellow = fixed(0xF4DF83)
    static let artBlue = fixed(0xAFCDF4)
    static let artMint = fixed(0x9DE1C8)
    static let artPeach = fixed(0xF4C292)
    static let artPurple = fixed(0xB7B1F4)
    static let artGreen = fixed(0xB9D9B0)

    static let shadow = adaptive(light: 0x16161A, dark: 0x000000)
    static let contrastBorder = adaptive(light: 0x77777E, dark: 0xC7C7CC)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light)
        })
    }

    private static func fixed(_ value: UInt32) -> Color {
        Color(uiColor: uiColor(value))
    }

    private static func uiColor(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum SlipSpacing {
    static let zero: CGFloat = 0
    static let hairline: CGFloat = 1
    static let micro: CGFloat = 2
    static let tiny: CGFloat = 4
    static let compact: CGFloat = 6
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let standard: CGFloat = 16
    static let screen: CGFloat = 20
    static let large: CGFloat = 24
    static let section: CGFloat = 32
    static let roomy: CGFloat = 40
    static let extraRoomy: CGFloat = 48
    static let hero: CGFloat = 64
    static let expansive: CGFloat = 80
    static let stage: CGFloat = 96
}

enum SlipRadius {
    static let crest: CGFloat = 12
    static let control: CGFloat = 14
    static let card: CGFloat = 20
    static let largeCard: CGFloat = 24
    static let tabBar: CGFloat = 34
    static let round: CGFloat = 999
}

enum SlipSize {
    static let minimumTap: CGFloat = 44
    static let smallIcon: CGFloat = 16
    static let icon: CGFloat = 20
    static let largeIcon: CGFloat = 26
    static let grabberWidth: CGFloat = 40
    static let grabberHeight: CGFloat = 5
    static let progressHeight: CGFloat = 6
    static let avatarSmall: CGFloat = 40
    static let avatar: CGFloat = 48
    static let avatarLarge: CGFloat = 64
    static let avatarHero: CGFloat = 72
    static let artSmall: CGFloat = 44
    static let art: CGFloat = 56
    static let artLarge: CGFloat = 72
    static let artHero: CGFloat = 112
    static let sealMark: CGFloat = 44
    static let sealMarkLarge: CGFloat = 54
    static let sealDisc: CGFloat = 56
    static let sealDiscLarge: CGFloat = 64
    static let buttonHeight: CGFloat = 58
    static let compactButtonHeight: CGFloat = 48
    static let tabBarHeight: CGFloat = 72
    static let segmentHeight: CGFloat = 44
    static let heroBannerHeight: CGFloat = 112
    static let choiceCardHeight: CGFloat = 198
    static let noteFieldHeight: CGFloat = 88
    static let rosterRowHeight: CGFloat = 64
    static let sheetCardHeight: CGFloat = 196
    static let receiptCardHeight: CGFloat = 258
    static let rankHeroHeight: CGFloat = 156
    static let statCardHeight: CGFloat = 74
    static let screenReferenceWidth: CGFloat = 393
    static let screenReferenceHeight: CGFloat = 852
}

enum SlipStroke {
    static let hairline: CGFloat = 0.5
    static let standard: CGFloat = 1
    static let emphasis: CGFloat = 2
    static let dashed: [CGFloat] = [4, 4]
}

enum SlipOpacity {
    static let faint: Double = 0.08
    static let subtle: Double = 0.16
    static let muted: Double = 0.32
    static let strong: Double = 0.72
    static let opaque: Double = 1
}

enum SlipShadow {
    static let cardColor = SlipColor.shadow.opacity(SlipOpacity.faint)
    static let cardRadius: CGFloat = 14
    static let cardY: CGFloat = 7
    static let floatingRadius: CGFloat = 24
    static let floatingY: CGFloat = 12
}

enum SlipMotion {
    static let pressScale: CGFloat = 0.97
    static let holdDuration: TimeInterval = 1.2
    static let pressDuration: TimeInterval = 0.15
    static let cancelDuration: TimeInterval = 0.2
    static let stampDuration: TimeInterval = 0.4
    static let revealDuration: TimeInterval = 0.5
    static let revealStagger: TimeInterval = 0.06
    static let stampStartScale: CGFloat = 1.15
}

