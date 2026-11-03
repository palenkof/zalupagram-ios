import Foundation
import UIKit
import Display

// ZalupaGram «Night sky» theme: the night theme with a ZalupaGram accent
// whose outgoing bubbles are this violet -> pink gradient. The last color
// differs by one unit when the bubble outlines are off, so the two variants
// are different themes and switching the outlines rebuilds the bubbles.
public let zalupaGramSkyBubbleColors: [UInt32] = [0x6d3fe6, 0xd35de6]
public let zalupaGramSkyPlainBubbleColors: [UInt32] = [0x6d3fe6, 0xd35de5]

private let zalupaGramSkyOutlineIncoming = UIColor(rgb: 0x8f6cff)
private let zalupaGramSkyOutlineOutgoing = UIColor(rgb: 0xf0a6ff)
private let zalupaGramSkyIncomingFill = UIColor(rgb: 0x14143c)

// Outlines are drawn 1.5 pt wide instead of the usual hairline.
let zalupaGramSkyOutlineWidth: CGFloat = 1.5

func zalupaGramIsSkyOutline(_ color: UIColor) -> Bool {
    let rgb = color.rgb
    return rgb == zalupaGramSkyOutlineIncoming.rgb || rgb == zalupaGramSkyOutlineOutgoing.rgb
}

// Navy incoming bubbles and, if they are on, the outlines.
func zalupaGramCustomizeSkyChat(_ chat: PresentationThemeChat, bubbleColors: [UInt32]) -> PresentationThemeChat {
    let colors = bubbleColors.map { $0 & 0xffffff }
    let outline: Bool
    if colors == zalupaGramSkyBubbleColors {
        outline = true
    } else if colors == zalupaGramSkyPlainBubbleColors {
        outline = false
    } else {
        return chat
    }
    let incoming = chat.message.incoming.bubble
    let outgoing = chat.message.outgoing.bubble
    let incomingStroke = outline ? zalupaGramSkyOutlineIncoming : UIColor.clear
    let outgoingStroke = outline ? zalupaGramSkyOutlineOutgoing : UIColor.clear
    return chat.withUpdated(
        message: chat.message.withUpdated(
            incoming: chat.message.incoming.withUpdated(
                bubble: incoming.withUpdated(
                    withWallpaper: incoming.withWallpaper.withUpdated(fill: [zalupaGramSkyIncomingFill], stroke: incomingStroke),
                    withoutWallpaper: incoming.withoutWallpaper.withUpdated(fill: [zalupaGramSkyIncomingFill], stroke: incomingStroke)
                )
            ),
            outgoing: chat.message.outgoing.withUpdated(
                bubble: outgoing.withUpdated(
                    withWallpaper: outgoing.withWallpaper.withUpdated(stroke: outgoingStroke),
                    withoutWallpaper: outgoing.withoutWallpaper.withUpdated(stroke: outgoingStroke)
                )
            )
        )
    )
}
