local M = { PLUGIN = "symbols", }

---@param pkg string
local function unload_package(pkg)
    local esc_pkg = pkg:gsub("([^%w])", "%%%1")
	for module_name, _ in pairs(package.loaded) do
		if string.find(module_name, esc_pkg) then
			package.loaded[module_name] = nil
		end
	end
end

---@param config table
function M.reload_plugin(config)
    unload_package(M.PLUGIN)
    require(M.PLUGIN).setup(config)
end

return M
