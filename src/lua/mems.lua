MEMS = {
    data = '',
    exts = {
        types       = '',
        enum_input  = '',
        enum_output = '',
    },
}

F = {
    ROOT__POS = function (me)
        MEMS.data = [[
typedef struct CEU_DATA_ROOT {
]]..MEMS.data..[[
} CEU_DATA_ROOT;
]]
    end,

    Block__PRE = function (me)
        local data = {}
        for _, dcl in ipairs(me.dcls) do
            if dcl.tag == 'Var' then
                if dcl.id ~= '_ret' then
                    local tp, is_alias = unpack(dcl)
                    local ptr = (is_alias and '*' or '')
                    dcl.id_ = dcl.id..'_'..dcl.n
                    data[#data+1] = TYPES.toc(tp)..ptr..' '..dcl.id_..';\n'
                end
            elseif dcl.tag == 'Ext' then
                MEMS.exts[#MEMS.exts+1] = dcl
            end
        end
        MEMS.data = MEMS.data..table.concat(data)
    end,

    Par_And = function (me)
        local data = ''
        for i=1, #me do
            data = data..'u8 __and_'..me.n..'_'..i..': 1;\n'
        end
        MEMS.data = MEMS.data..data
    end,

    Await_Wclock = function (me)
        MEMS.data = MEMS.data..'s32 __wclk_'..me.n..';\n'
    end,

    Loop = function (me)
        local max = unpack(me)
    end,
    Loop_Num = function (me)
        local max, i, fr, dir, to, step, body = unpack(me)

        local data = {}

        if to.tag ~= 'ID_any' then
            data[#data+1]= 'int __lim_'..me.n..';\n'
        end

        MEMS.data = MEMS.data..table.concat(data)
    end,
}

AST.visit(F)

for _, dcl in ipairs(MEMS.exts) do
    local Typelist, inout, id = unpack(dcl)
    dcl.id_ = string.upper('CEU_'..inout..'_'..id)

    if inout == 'input' then
        MEMS.exts.enum_input  = MEMS.exts.enum_input..dcl.id_..',\n'
    else
        MEMS.exts.enum_output = MEMS.exts.enum_output..dcl.id_..',\n'
    end

    local data = 'typedef struct tceu_'..inout..'_'..dcl.id..' {\n'
    for i,Type in ipairs(Typelist) do
        data = data..'    '..TYPES.toc(Type)..' _'..i..';\n'
    end
    data = data..'} tceu_'..inout..'_'..dcl.id..';\n'

    MEMS.exts.types = MEMS.exts.types..data
end
