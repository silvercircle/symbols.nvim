local H = {}

function H.open_file(child, path)
    child.type_keys(":e " .. path .. "<cr>")
    child.bo.readonly = true
end

H.eq = MiniTest.expect.equality

return H
