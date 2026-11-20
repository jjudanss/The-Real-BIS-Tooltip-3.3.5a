THE REAL BIS-TOOLTIP 3.3.5a
First Release — Version 1.0.0

OVERVIEW
The Real BIS-Tooltip 3.3.5a is a Best-in-Slot browser for the original World of Warcraft: Wrath of the Lich King 3.3.5a client (Interface 30300). It uses the supplied corrected BiS spreadsheet as its recommendation source and includes equipment and glyph icons, native hover tooltips, class/build browsing, Dressing Room previews, and a movable minimap button with custom artwork.

SOURCE DATA
- Authoritative recommendation source: 
BiS list by Kama: https://docs.google.com/spreadsheets/d/1yGF4pXkvonaLNjcB1-V1nwKV5hPDn6octfGp5MBHZi4/edit?pli=1&gid=616501968#gid=616501968.
- The source contains 10 class worksheets and 37 specialization/build columns.
- Recommendation wording, alternatives, class/build assignments, and glyph selections are retained from the workbook.
- Supplemental item IDs and aliases are included so the client can request item records even when an item has never been collected by the character.
- Confirmed Heroic item mappings are included where an appropriate Heroic counterpart exists. Items from systems without a corresponding same-name Heroic version are retained as listed.

FEATURES
- Browse all 10 classes and 37 source builds using the CLASS and SPEC / BUILD selectors.
- Automatically detect the logged-in character's class and suggest a build from the active talent tree where the workbook supports a reliable match.
- Manually select other classes and builds.
- Display equipment and glyph recommendations with item icons where the game client returns item data.
- Hover an equipment or glyph entry to display the native World of Warcraft item tooltip. The tooltip feature remains active even though the browser does not display an instructional hover message.
- Use Ctrl-click (or the player's configured Dressing Room modifier) on equipment entries to preview items. Shift-click (or the configured chat-link modifier) inserts an item link into chat.
- Use the custom BIS minimap button: left-click opens/closes the browser, right-click toggles the all-class/your-class item-tooltip filter, and dragging changes its saved position.
- Load item information progressively and track loaded, pending, and failed lookups.
- Retry failed lookups without repeatedly requesting items that are already loaded.

INTERFACE
The browser uses a larger branded layout with the custom medallion at the upper-left and the addon title centered at the top. The Player / Viewing status line and the instructional hover-text line are intentionally hidden to provide a cleaner interface and more room for recommendations. The item-catalog loading status and Retry Failed button remain available. Hiding the instructional text does not disable item or glyph tooltips.

INSTALLATION
1. Exit World of Warcraft completely.
2. Extract the TheRealBISTooltip folder from this archive.
3. Place it in World of Warcraft\Interface\AddOns\.
4. Confirm that the final path is World of Warcraft\Interface\AddOns\TheRealBISTooltip\TheRealBISTooltip.toc.
5. Launch the 3.3.5a client and enable The Real BIS-Tooltip 3.3.5a at the character-selection screen.
6. Log in and type /trbis to open the browser.

SLASH COMMANDS
- /trbis — Open or close the BiS browser.
- /trbis mine — Restrict additional item-tooltip BiS matches to your character's class.
- /trbis all — Show additional item-tooltip BiS matches from every class.
- /trbis auto — Re-detect character class and suggested talent-tree build.
- /trbis refresh — Queue unresolved item lookups and retry failures.
- /trbis retry — Retry failed item lookups only.
- /trbis status — Print detected class/tree and item-catalog status in chat.
- Use the class and SPEC / BUILD selectors to browse the complete source workbook.

ITEM DATA NOTES
The addon's item lookup table maps workbook names to Wrath item IDs and known aliases. On private servers, custom item templates or modified IDs may differ from standard Wrath data. If the realm does not return an item record, that item may continue to show a question-mark icon and its full native tooltip cannot be displayed until a valid ID or item link is available.

The Heroic audit files included in this folder document the same-name difficulty mapping review. They are reference material; the addon does not need them to run.

COMPATIBILITY
- World of Warcraft: Wrath of the Lich King 3.3.5a.
- Client build target: 12340.
- Interface: 30300.
- No external addon libraries or dependencies are required.

TESTING NOTE
This package has been checked for its file structure and metadata. Actual behavior, item data availability, and appearance should be confirmed in the target 3.3.5a client and private server environment.
