local M = {
    PLUGIN = "my-outline",
    ENV_VAR = "MY_OUTLINE_DEV",
}

---@alias dev.Env "dev" | "prod"
---@return dev.Env
function M.env()
    local var = os.getenv(M.ENV_VAR)
    return var ~= nil and "dev" or "prod"
end

---@param pkg string
local function unload_package(pkg)
    local esc_pkg = pkg:gsub("([^%w])", "%%%1")
	for module_name, _ in pairs(package.loaded) do
		if string.find(module_name, esc_pkg) then
			package.loaded[module_name] = nil
		end
	end
end

function M.reload_plugin()
    unload_package(M.PLUGIN)
    require(M.PLUGIN).setup()
end

function M.setup()
    vim.keymap.set("n", ",r", "<cmd>luafile lua/" .. M.PLUGIN .. "/dev.lua<CR>")
    vim.keymap.set("n", ",w", M.reload_plugin)
end

return M
