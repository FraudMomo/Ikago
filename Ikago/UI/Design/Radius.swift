import CoreGraphics

/// The corner radii Ikago uses, smallest to largest. Every rounded shape in the chrome takes one of these, so corners
/// read as one family: the larger the surface, the larger its radius, and a shape nested in another with padding `p`
/// uses the outer radius minus `p` where that lands on the scale.
enum Radius {
    /// Rows inside menus and lists on a card (suggestions, chips, thumbnails).
    static let inner: CGFloat = 6
    /// Small controls: fields in sheets, buttons, tiles in mockups.
    static let control: CGFloat = 8
    /// Sidebar rows, group headers and pills, the address fields, rail tiles, hover fills.
    static let row: CGFloat = 10
    /// The page, the sidebar panel, popovers, dropdowns, the hover card, the assistant.
    static let card: CGFloat = 12
    /// Sheets and large floating panels: modals, the downloads list, link previews.
    static let sheet: CGFloat = 16
    /// The floating command bar, after Spotlight: a capsule at its 52 pt resting height, a soft card once it opens.
    static let bar: CGFloat = 26
}
