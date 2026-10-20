-- Schreibt die Änderungen der neuesten Version auf Englisch als Markdown, für CurseForge und GitHub.
-- Quelle ist der Changelog in PrioMeister/Main.lua, übersetzt über die Tabelle EN in Locale.lua.
-- Aufruf im Hauptordner: lua5.1 scripts/changelog.lua > CHANGELOG.md
-- Die Tests vergleichen CHANGELOG.md mit dieser Ausgabe.

local function read(path)
	local fh = assert(io.open(path, "rb"))
	local text = fh:read("*a")
	fh:close()
	return text
end

local function render(dir)
	local main = read(dir .. "/PrioMeister/Main.lua")
	local body = assert(main:match("\nlocal CHANGELOG = (.-)\nUI%.CHANGELOG = CHANGELOG"), "Changelog in Main.lua nicht gefunden")
	local changelog = assert(loadstring("return " .. body))()
	local ns = {}
	assert(loadfile(dir .. "/PrioMeister/Locale.lua"))("PrioMeister", ns)
	local version, date, changes = changelog[1][1], changelog[1][2], changelog[1][3]
	local d, m, y = date:match("^(%d+)%.(%d+)%.(%d+)$")
	local out = { ("# PrioMeister %s (%s-%s-%s)"):format(version, y, m, d), "" }
	for _, change in ipairs(changes) do
		out[#out + 1] = "- " .. assert(ns.EN[change], "keine Übersetzung: " .. change)
	end
	return table.concat(out, "\n") .. "\n"
end

if (...) == "module" then return render end
local dir = arg and arg[0] and arg[0]:match("^(.*)/scripts/[^/]*$") or "."
io.write(render(dir))
