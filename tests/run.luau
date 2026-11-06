--!strict
-- Tiny test harness. Run with: lune run tests/run
local fs = require("@lune/fs")
local process = require("@lune/process")

local passed, failed = 0, 0
local failures: { string } = {}

local function fmt(v: any): string
	if type(v) == "table" then
		local parts = {}
		for k, x in v do
			table.insert(parts, tostring(k) .. "=" .. tostring(x))
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

local t = {}
local current = ""

function t.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, current .. " > " .. name .. ": " .. tostring(err))
	end
end

function t.eq(actual: any, expected: any, msg: string?)
	if actual ~= expected then
		error(`{msg or "eq"}: expected {fmt(expected)}, got {fmt(actual)}`, 2)
	end
end

function t.near(actual: number, expected: number, eps: number?, msg: string?)
	if math.abs(actual - expected) > (eps or 1e-6) then
		error(`{msg or "near"}: expected {expected}, got {actual}`, 2)
	end
end

function t.ok(cond: any, msg: string?)
	if not cond then
		error(msg or "expected truthy", 2)
	end
end

local filter = process.args[1]
local files = fs.readDir("tests")
table.sort(files)
for _, file in files do
	if string.sub(file, -10) == ".spec.luau" and (filter == nil or string.find(file, filter, 1, true)) then
		current = file
		local spec = (require :: any)("./" .. string.sub(file, 1, -6))
		spec(t)
	end
end

print(`{passed} passed, {failed} failed`)
for _, f in failures do
	print("  FAIL " .. f)
end
process.exit(if failed > 0 then 1 else 0)
