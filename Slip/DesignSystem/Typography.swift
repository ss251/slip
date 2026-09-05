import SwiftUI

enum SlipFont {
    static let large = Font.largeTitle.weight(.bold)
    static let title = Font.title.weight(.bold)
    static let title2 = Font.title2.weight(.bold)
    static let title3 = Font.title3
    static let title3Bold = Font.title3.weight(.bold)
    static let headline = Font.headline
    static let body = Font.body
    static let bodyBold = Font.body.weight(.semibold)
    static let subheadline = Font.subheadline
    static let subheadlineBold = Font.subheadline.weight(.semibold)
    static let footnote = Font.footnote
    static let footnoteBold = Font.footnote.weight(.semibold)
    static let caption = Font.caption
    static let captionBold = Font.caption.weight(.semibold)
    static let machine = Font.custom("JetBrainsMono-Regular", size: 12, relativeTo: .caption)
    static let tab = Font.caption2.weight(.medium)
    // Non-text chrome glyphs retain their visual size inside fixed 44-point targets.
    static let chromeIcon = Font.system(size: 22, weight: .bold)
    static let avatarInitial = Font.system(size: 17, weight: .semibold)
    static let smallChromeIcon = Font.system(size: 17, weight: .semibold)
    static let artworkCaption = Font.system(size: 15, weight: .semibold)
}
