import Foundation
import UIKit
import Display

// ZalupaGram «Sky» theme: the night theme with a ZalupaGram accent whose
// outgoing bubbles are this violet -> pink gradient.
public let zalupaGramSkyBubbleColors: [UInt32] = [0x6d3fe6, 0xd35de6]

private let zalupaGramSkyOutlineIncoming = UIColor(rgb: 0x8f6cff)
private let zalupaGramSkyOutlineOutgoing = UIColor(rgb: 0xf0a6ff)
private let zalupaGramSkyIncomingFill = UIColor(rgb: 0x14143c)

// Outlines are drawn 1.5 pt wide instead of the usual hairline.
let zalupaGramSkyOutlineWidth: CGFloat = 1.5

func zalupaGramIsSkyOutline(_ color: UIColor) -> Bool {
    let rgb = color.rgb
    return rgb == zalupaGramSkyOutlineIncoming.rgb || rgb == zalupaGramSkyOutlineOutgoing.rgb
}

// Navy incoming bubbles and the outlines.
func zalupaGramCustomizeSkyChat(_ chat: PresentationThemeChat, bubbleColors: [UInt32]) -> PresentationThemeChat {
    if bubbleColors.map({ $0 & 0xffffff }) != zalupaGramSkyBubbleColors {
        return chat
    }
    let incoming = chat.message.incoming.bubble
    let outgoing = chat.message.outgoing.bubble
    let incomingStroke = zalupaGramSkyOutlineIncoming
    let outgoingStroke = zalupaGramSkyOutlineOutgoing
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
