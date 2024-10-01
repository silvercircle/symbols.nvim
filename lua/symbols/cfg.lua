local M = {}

---@alias DevAction "reload" | "debug"

---@class DevConfig
---@field enabled boolean
---@field keymaps table<string, DevAction>

---@class Config
---@field dev DevConfig

---@type Config
M.default = {
    dev = {
        enabled = false,
        keymaps = {},
    }
}

return M
