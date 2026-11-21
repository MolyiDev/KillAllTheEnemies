-- Maps a key to its keycap picture, keyboard and mouse. The art is Kenney's input prompts, full white faces tinted
-- where they are drawn. These ids are BeACastleLord's uploads (Assets/ui/keys there): an image, unlike an animation,
-- loads in any experience, so they are reused rather than uploaded twice. Its controller glyphs are not mapped until
-- this game binds a controller (GDD 13: inputs still TBD).
--
-- Look a key up by KeyCode (GetForKeyCode), not by indexing the table: the cap a board prints comes first, so a
-- hint on AZERTY points at the key the player actually sees.
local UserInputService = game:GetService("UserInputService")

local KeyImages = {}

local Images: { [string]: string } = {
	-- Keyboard letters (KeyCode.Name, and the same string GetStringForKeyCode returns on a
	-- QWERTY layout; on AZERTY the string wins, so the picture matches the printed cap).
	["A"] = "rbxassetid://111746197392411",
	["B"] = "rbxassetid://100815771943455",
	["C"] = "rbxassetid://137838237705961",
	["D"] = "rbxassetid://95308849927252",
	["E"] = "rbxassetid://122133947416115",
	["F"] = "rbxassetid://136349583915663",
	["G"] = "rbxassetid://132141016033703",
	["H"] = "rbxassetid://74491296955695",
	["I"] = "rbxassetid://84314965344256",
	["J"] = "rbxassetid://123162262943327",
	["K"] = "rbxassetid://99069327680163",
	["L"] = "rbxassetid://80501305175776",
	["M"] = "rbxassetid://105914409644356",
	["N"] = "rbxassetid://137388712996370",
	["O"] = "rbxassetid://77262023331083",
	["P"] = "rbxassetid://88675218845143",
	["Q"] = "rbxassetid://139382520315016",
	["R"] = "rbxassetid://116722496765979",
	["S"] = "rbxassetid://93647934317689",
	["T"] = "rbxassetid://92555009899684",
	["U"] = "rbxassetid://91054180242460",
	["V"] = "rbxassetid://80958730776255",
	["W"] = "rbxassetid://73205714255767",
	["X"] = "rbxassetid://78161411577826",
	["Y"] = "rbxassetid://133096226950973",
	["Z"] = "rbxassetid://98863679350519",

	-- Number row. KeyCode.Name spells these out, which is the fallback the lookup lands on.
	["Zero"] = "rbxassetid://95855478678105",
	["One"] = "rbxassetid://97862999548470",
	["Two"] = "rbxassetid://102075188115460",
	["Three"] = "rbxassetid://87310793652445",
	["Four"] = "rbxassetid://87288023049543",
	["Five"] = "rbxassetid://86718006891533",
	["Six"] = "rbxassetid://98678813892257",
	["Seven"] = "rbxassetid://125325200014346",
	["Eight"] = "rbxassetid://122240783207997",
	["Nine"] = "rbxassetid://118298337174847",

	-- Function row
	["F1"] = "rbxassetid://114032526322581",
	["F2"] = "rbxassetid://71828218459020",
	["F3"] = "rbxassetid://125876626593653",
	["F4"] = "rbxassetid://105015117920292",
	["F5"] = "rbxassetid://111458036455302",
	["F6"] = "rbxassetid://88553464283485",
	["F7"] = "rbxassetid://97569484727854",
	["F8"] = "rbxassetid://140517731523316",
	["F9"] = "rbxassetid://89270811722398",
	["F10"] = "rbxassetid://108071099086264",
	["F11"] = "rbxassetid://119340530300267",
	["F12"] = "rbxassetid://90926111124834",

	-- Modifiers. Left and right are one picture each: the cap says SHIFT either way.
	["LeftShift"] = "rbxassetid://72306903277525",
	["RightShift"] = "rbxassetid://72306903277525",
	["LeftControl"] = "rbxassetid://109981512728881",
	["RightControl"] = "rbxassetid://109981512728881",
	["LeftAlt"] = "rbxassetid://111868037479129",
	["RightAlt"] = "rbxassetid://111868037479129",
	["LeftMeta"] = "rbxassetid://72485537519372",
	["RightMeta"] = "rbxassetid://72485537519372",
	["CapsLock"] = "rbxassetid://74624383038483",

	-- Editing and whitespace
	["Space"] = "rbxassetid://83349981220732",
	["Tab"] = "rbxassetid://137442026171588",
	["Return"] = "rbxassetid://93116156619343",
	["KeypadEnter"] = "rbxassetid://123363875777804",
	["KeypadPlus"] = "rbxassetid://76264520047758",
	["Backspace"] = "rbxassetid://86853875693099",
	["Delete"] = "rbxassetid://137026552901851",
	["Insert"] = "rbxassetid://109942767194592",
	["Escape"] = "rbxassetid://124553284560343",

	-- Navigation
	["Up"] = "rbxassetid://126799277164148",
	["Down"] = "rbxassetid://102209934104512",
	["Left"] = "rbxassetid://118918192171697",
	["Right"] = "rbxassetid://71107218505001",
	["Home"] = "rbxassetid://100216782909440",
	["End"] = "rbxassetid://109967793367356",
	["PageUp"] = "rbxassetid://137043856973368",
	["PageDown"] = "rbxassetid://98122868112955",

	-- Locks and the system row
	["NumLock"] = "rbxassetid://82635495560753",
	["ScrollLock"] = "rbxassetid://113099318732515",
	["Pause"] = "rbxassetid://75339393011488",
	["Break"] = "rbxassetid://75867524885642",
	["Print"] = "rbxassetid://138759040729959",

	-- Punctuation. GetStringForKeyCode answers with the character itself (";", "/"), which misses
	-- and drops through to KeyCode.Name, so these are spelled the way the enum spells them.
	["Backquote"] = "rbxassetid://98382918598477",
	["Tilde"] = "rbxassetid://98382918598477",
	["Minus"] = "rbxassetid://86345276373677",
	["Underscore"] = "rbxassetid://84971851503742",
	["Equals"] = "rbxassetid://72996437102605",
	["Plus"] = "rbxassetid://114671008975121",
	["LeftBracket"] = "rbxassetid://136026327750495",
	["RightBracket"] = "rbxassetid://101195654239815",
	["LessThan"] = "rbxassetid://104401024735428",
	["GreaterThan"] = "rbxassetid://116825859429449",
	["BackSlash"] = "rbxassetid://109801680423766",
	["Slash"] = "rbxassetid://129087463406105",
	["Semicolon"] = "rbxassetid://86888267441665",
	["Colon"] = "rbxassetid://108390301397589",
	["Quote"] = "rbxassetid://77644114030957",
	["QuotedDouble"] = "rbxassetid://86727312736475",
	["Comma"] = "rbxassetid://100695255002999",
	["Period"] = "rbxassetid://98359353579158",
	["Question"] = "rbxassetid://121208004485825",
	["Asterisk"] = "rbxassetid://81241577385723",
	["Caret"] = "rbxassetid://109384315924312",

	-- Mouse buttons (KeyCode.Name).
	["MouseLeftButton"] = "rbxassetid://101071046280158",
	["MouseRightButton"] = "rbxassetid://111725509481142",
	["MouseMiddleButton"] = "rbxassetid://73422858206875",
	["MouseBackButton"] = "rbxassetid://86054077436456",
}

-- The picture for a keycode, or "" when there is none: the cap as this board prints it, falling back to the key's
-- name when the board has nothing to print (modifiers, mouse buttons) or prints a digit (the number row).
function KeyImages.GetForKeyCode(keyCode: Enum.KeyCode): string
	local image = Images[UserInputService:GetStringForKeyCode(keyCode)]
	if image then return image end
	return Images[keyCode.Name] or ""
end

return table.freeze(KeyImages)
