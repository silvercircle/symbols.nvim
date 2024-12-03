local H = dofile("tests/utils.lua")

local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
    end,
    pre_case = function()
        child.restart({ "-u", "tests/nvim_test/init.lua" })
        child.bo.readonly = false
    end,
    post_once = child.stop,
  },

})

local function test_file(path)
    H.open_file(child, path)
    child.type_keys(":Symbols<cr>")
    child.type_keys("zR")
    MiniTest.expect.reference_screenshot(child.get_screenshot())
end

T["markdown"] = function() test_file("tests/examples/headings.md") end
T["vimdoc"] = function() test_file("tests/examples/mini-test.txt") end
T["org"] = function() test_file("tests/examples/example.org") end
T["json"] = function() test_file("tests/examples/morty.json") end
T["json-lines"] = function() test_file("tests/examples/example.jsonl") end

return T
