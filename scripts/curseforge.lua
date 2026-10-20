-- Schreibt die Beschreibung für CurseForge: erst README.en.md, dann die deutsche Fassung aus
-- curseforge/beschreibung.de.md. CurseForge verlangt Englisch zuerst. Relative Links zeigen danach
-- auf GitHub. Aufruf im Hauptordner: lua5.1 scripts/curseforge.lua > curseforge/beschreibung.md
-- Die Tests vergleichen curseforge/beschreibung.md mit dieser Ausgabe. Das Release ändert die
-- Beschreibung auf CurseForge nicht, sie wird dort von Hand eingefügt.

local REPO = "https://github.com/andi79h/PrioMeister/blob/main/"

local function read(path)
	local fh = assert(io.open(path, "rb"))
	local text = fh:read("*a")
	fh:close()
	return text
end

local function absolute(text)
	text = text:gsub("%]%(([^)#:]+)%)", function(path) return "](" .. REPO .. path .. ")" end)
	return (text:gsub("%s+$", ""))
end

local function render(dir)
	return absolute(read(dir .. "/README.en.md")) .. "\n\n---\n\n" .. absolute(read(dir .. "/curseforge/beschreibung.de.md")) .. "\n"
end

if (...) == "module" then return render end
local dir = arg and arg[0] and arg[0]:match("^(.*)/scripts/[^/]*$") or "."
io.write(render(dir))
