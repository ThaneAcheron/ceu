MEM = {
    adts = '',
    adts_init = '',
    clss = '',
    native_pre = '',
}

function SPC ()
    return string.rep(' ',AST.iter()().__depth*2)
end

function pred_sort (v1, v2)
    return (v1.len or TP.types.word.len) > (v2.len or TP.types.word.len)
end

F = {
    Host = function (me)
        local pre, code = unpack(me)
        -- unescape `##´ => `#´
        local src = string.gsub(code, '^%s*##',  '#')
              src = string.gsub(src,   '\n%s*##', '\n#')
        CLS().native[pre] = CLS().native[pre] .. [[

#line ]]..me.ln[2]..' "'..me.ln[1]..[["
]] .. src
    end,

    Dcl_adt_pre = function (me)
        local id, op = unpack(me)
        me.struct = 'typedef '
        me.auxs   = {}
        if op == 'union' then
            me.struct = me.struct..[[
struct CEU_]]..id..[[ {
    u8 tag;
    union {
]]
            me.enum = { 'NONE' }    -- reserves 0 to catch more bugs
        end

        me.auxs[#me.auxs+1] = [[
#ifdef CEU_ADTS_NEWS
#ifdef CEU_ADTS_NEWS_MALLOC
void CEU_]]..id..'_free_dynamic (CEU_'..id..[[* me);
#endif
#ifdef CEU_ADTS_NEWS_POOL
void CEU_]]..id..'_free_static (CEU_'..id..[[* me, void* pool);
#endif
#endif
]]
    end,
    Dcl_adt = function (me)
        local id, op = unpack(me)
        if op == 'union' then
            me.struct = me.struct .. [[
    };
}
]]
            me.enum = 'enum {\n'..table.concat(me.enum,',\n')..'\n};\n'
        else
            me.struct = string.sub(me.struct, 1, -3)    -- remove leading ';'
        end

        local free = [[
#ifdef CEU_ADTS_NEWS
#ifdef CEU_ADTS_NEWS_MALLOC
void CEU_]]..id..'_free_dynamic (CEU_'..id..[[* me) {
]]
        if op == 'struct' then
            free = free .. [[
    ceu_out_realloc(me, 0);
]]
        else
            assert(op == 'union')
            free = free .. [[
    switch (me->tag) {
]]
            for _, tag in ipairs(me.tags) do
                local id_tag = string.upper(id..'_'..tag)
                free = free .. [[
        case CEU_]]..id_tag..[[:
]]
                if me.is_rec and tag==me.tags[1] then
                    free = free .. [[
            /* base case */
]]
                else
                    free = free .. [[
            CEU_]]..id_tag..[[_free_dynamic(me);
]]
                end
                free = free .. [[
            break;
]]
            end
            free = free .. [[
    }
]]
        end
        free = free .. [[
}
#endif
#ifdef CEU_ADTS_NEWS_POOL
void CEU_]]..id..'_free_static (CEU_'..id..[[* me, void* pool) {
]]
        if op == 'struct' then
            free = free .. [[
    ceu_pool_free(pool, (void*)me);
]]
        else
            assert(op == 'union')
            free = free .. [[
    switch (me->tag) {
]]
            for _, tag in ipairs(me.tags) do
                local id_tag = string.upper(id..'_'..tag)
                free = free .. [[
        case CEU_]]..id_tag..[[:
]]
                if me.is_rec and tag==me.tags[1] then
                    free = free .. [[
            /* base case */
]]
                else
                    free = free .. [[
            CEU_]]..id_tag..[[_free_static(me, pool);
]]
                end
                free = free .. [[
            break;
]]
            end
            free = free .. [[
    }
]]
        end
        free = free .. [[
}
#endif
#endif
]]

        me.auxs[#me.auxs+1] = free
        me.auxs   = table.concat(me.auxs,'\n')..'\n'
        me.struct = me.struct..' CEU_'..id..';'
        MEM.adts = MEM.adts..'\n'..(me.enum or '')..'\n'..
                                   me.struct..'\n'..
                                   me.auxs..'\n'

        -- declare a static BASE instance
        if me.is_rec then
            MEM.adts = MEM.adts..[[
static CEU_]]..id..[[ CEU_]]..string.upper(id)..[[_BASE;
]]
            MEM.adts_init = MEM.adts_init .. [[
CEU_]]..string.upper(id)..[[_BASE.tag = CEU_]]..string.upper(id..'_'..me.tags[1])..[[;
]]
        end
    end,
    Dcl_adt_tag_pre = function (me)
        local top = AST.par(me, 'Dcl_adt')
        local id = unpack(top)
        local tag = unpack(me)
        local enum = 'CEU_'..string.upper(id)..'_'..tag
        top.enum[#top.enum+1] = enum
        top.auxs[#top.auxs+1] = [[
CEU_]]..id..'* '..enum..'_assert (CEU_'..id..[[* me) {
    ceu_out_assert(me->tag == ]]..enum..[[);
    return me;
}
]]

        if top.is_rec and top.tags[1]==tag then
            return  -- base case, no free
        end

        local free = [[
#ifdef CEU_ADTS_NEWS
#ifdef CEU_ADTS_NEWS_MALLOC
void ]]..enum..'_free_dynamic (CEU_'..id..[[* me) {
]]

        -- free all my recursive fields
        for _,item in ipairs(top.tags[tag].tup) do
            local _, tp, _ = unpack(item)
            if TP.tostr(tp) == id..'*' then
                free = free .. [[
    CEU_]]..id..[[_free_dynamic(me->]]..tag..'.'..item.var_id..[[);
]]
            end
        end

        -- free myself
        free = free .. [[
    ceu_out_realloc(me, 0);
}
#endif
#ifdef CEU_ADTS_NEWS_POOL
void ]]..enum..'_free_static (CEU_'..id..[[* me, void* pool) {
]]

        -- free all my recursive fields
        for _,item in ipairs(top.tags[tag].tup) do
            local _, tp, _ = unpack(item)
            if TP.tostr(tp) == id..'*' then
                free = free .. [[
    CEU_]]..id..[[_free_static(me->]]..tag..'.'..item.var_id..[[, pool);
]]
            end
        end

        -- free myself
        free = free .. [[
    ceu_pool_free(pool, (void*)me);
}
#endif
#endif
]]
        top.auxs[#top.auxs+1] = free
    end,

    Dcl_cls_pre = function (me)
        me.struct = [[
typedef struct CEU_]]..me.id..[[ {
  struct tceu_org org;
  tceu_trl trls_[ ]]..me.trails_n..[[ ];
]]
        me.native = { [true]='', [false]='' }
        me.funs = ''
    end,
    Dcl_cls_pos = function (me)
        if me.is_ifc then
            me.struct = 'typedef void '..TP.toc(me.tp)..';\n'
            -- interface full declarations must be delayed to after its impls.  
            local struct = [[
typedef union CEU_]]..me.id..[[_delayed {
]]
            for k, v in pairs(me.matches) do
                if v then
                    struct = struct..'\t'..TP.toc(k.tp)..' '..k.id..';\n'
                end
            end
            struct = struct .. [[
} CEU_]]..me.id..[[_delayed;
]]
            -- TODO: HACK_4: delayed declaration until use
            me.struct_delayed = struct .. '\n'
        else
            me.struct  = me.struct..'\n} '..TP.toc(me.tp)..';\n'
        end

        -- native/pre goes before everything
        MEM.native_pre = MEM.native_pre ..  me.native[true]

        if me.id ~= 'Main' then
            -- native goes after class declaration
            MEM.clss = MEM.clss .. me.native[false] .. '\n'
        end
        MEM.clss = MEM.clss .. me.struct .. '\n'

        MEM.clss = MEM.clss .. me.funs .. '\n'
--DBG('===', me.id, me.trails_n)
--DBG(me.struct)
--DBG('======================')
    end,

    Dcl_fun = function (me)
        local _, _, ins, out, id, blk = unpack(me)
        local cls = CLS()

        -- input parameters (void* _ceu_go->org, int a, int b)
        local dcl = { 'tceu_app* _ceu_app', 'tceu_org* __ceu_org' }
        for _, v in ipairs(ins) do
            local _, tp, id = unpack(v)
            dcl[#dcl+1] = TP.toc(tp)..' '..(id or '')
        end
        dcl = table.concat(dcl,  ', ')

        -- TODO: static?
        me.id = 'CEU_'..cls.id..'_'..id
        me.proto = [[
]]..TP.toc(out)..' '..me.id..' ('..dcl..[[)
]]
        if OPTS.os and ENV.exts[id] and ENV.exts[id].pre=='output' then
            -- defined elsewhere
        else
            cls.funs = cls.funs..'static '..me.proto..';\n'
        end
    end,

    Stmts_pre = function (me)
        local cls = CLS()
        if cls then
            cls.struct = cls.struct..SPC()..'union {\n'
        end
    end,
    Stmts_pos = function (me)
        local cls = CLS()
        if cls then
            cls.struct = cls.struct..SPC()..'};\n'
        end
    end,

    Block_pos = function (me)
        local top = AST.par(me,'Dcl_adt') or CLS()
        local tag = ''
        if top.tag == 'Dcl_adt' then
            local n = AST.par(me, 'Dcl_adt_tag')
            if n then
                tag = unpack(n)
            end
        end
        top.struct = top.struct..SPC()..'} '..tag..';\n'
    end,
    Block_pre = function (me)
        local top = AST.par(me,'Dcl_adt') or CLS()

        top.struct = top.struct..SPC()..'struct { /* BLOCK ln='..me.ln[2]..' */\n'

        if me.fins then
            for i=1, #me.fins do
            top.struct = top.struct .. SPC()
                            ..'u8 __fin_'..me.n..'_'..i..': 1;\n'
            end
        end

        for _, var in ipairs(me.vars) do
            local len
            --if var.isTmp or var.pre=='event' then  --
            if var.isTmp then --
                len = 0
            elseif var.pre == 'event' then --
                len = 1   --
            elseif var.pre=='pool' and (type(var.tp.arr)=='table') then
                len = 10    -- TODO: it should be big
            elseif var.cls or var.adt then
                len = 10    -- TODO: it should be big
                --len = (var.tp.arr or 1) * ?
            elseif var.tp.arr then
                len = 10    -- TODO: it should be big
--[[
                local _tp = TP.deptr(var.tp)
                len = var.tp.arr * (TP.deptr(_tp) and TP.types.pointer.len
                             or (ENV.c[_tp] and ENV.c[_tp].len
                                 or TP.types.word.len)) -- defaults to word
]]
            elseif var.tp.ptr>0 or REF(var.tp) then
                len = TP.types.pointer.len
            else
                len = ENV.c[var.tp.id].len
            end
            var.len = len
        end

        -- sort offsets in descending order to optimize alignment
        -- TODO: previous org metadata
        local sorted = { unpack(me.vars) }
        if me~=top.blk_ifc and top.tag~='Dcl_adt' then
            table.sort(sorted, pred_sort)   -- TCEU_X should respect lexical order
        end

        for _, var in ipairs(sorted) do
            local tp = TP.toc(var.tp)

            if var.inTop then
                var.id_ = var.id
                    -- id's inside interfaces are kept (to be used from C)
            else
                var.id_ = var.id .. '_' .. var.n
                    -- otherwise use counter to avoid clash inside struct/union
            end

            if top.id == var.tp.id then
                tp = 'struct '..tp  -- for types w/ pointers for themselves
            end

            if var.pre=='var' and (not var.isTmp) then
                local dcl = [[
#line ]]..var.ln[2]..' "'..var.ln[1]..[["
]]
                if var.tp.arr then
                    local tp = string.sub(tp,1,-2)  -- remove leading `*´
                    ASR(type(var.tp.arr)=='table' and var.tp.arr.cval,
                        me, 'invalid array dimension')
                    dcl = dcl .. tp..' '..var.id_..'['..var.tp.arr.cval..']'
                else
                    dcl = dcl .. tp..' '..var.id_
                end
                top.struct = top.struct..SPC()..'  '..dcl..';\n'
            elseif var.pre=='pool' then
                local T = var.cls or var.adt

                -- static pool: "var T[N] ts"
                if type(var.tp.arr) == 'table' then
                    local T = ENV.clss[var.tp.id] or ENV.adts[var.tp.id]
                    if T.is_ifc then
                        -- TODO: HACK_4: delayed declaration until use
                        MEM.clss = MEM.clss .. T.struct_delayed .. '\n'
                        T.struct_delayed = ''
                        top.struct = top.struct .. [[
CEU_POOL_DCL(]]..var.id_..',CEU_'..var.tp.id..'_delayed,'..var.tp.arr.sval..[[)
]]
                               -- TODO: bad (explicit CEU_)
                    else
                        top.struct = top.struct .. [[
CEU_POOL_DCL(]]..var.id_..',CEU_'..var.tp.id..','..var.tp.arr.sval..[[)
]]
                               -- TODO: bad (explicit CEU_)
                    end
                end
            end

            -- pointers ini/end to list of orgs
            if var.cls then
                top.struct = top.struct .. SPC() ..
                   'tceu_org_lnk __lnks_'..me.n..'_'..var.trl_orgs[1]..'[2];\n'
                    -- see val.lua for the (complex) naming
            end
        end
    end,

    ParOr_pre = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'struct {\n'
    end,
    ParOr_pos = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'};\n'
    end,
    ParAnd_pre = 'ParOr_pre',
    ParAnd_pos = 'ParOr_pos',
    ParEver_pre = 'ParOr_pre',
    ParEver_pos = 'ParOr_pos',

    ParAnd = function (me)
        local cls = CLS()
        for i=1, #me do
            cls.struct = cls.struct..SPC()..'u8 __and_'..me.n..'_'..i..': 1;\n'
        end
    end,

    Await = function (me)
        local _, dt = unpack(me)
        if dt then
            local cls = CLS()
            cls.struct = cls.struct..SPC()..'s32 __wclk_'..me.n..';\n'
        end
    end,

    Thread_pre = 'ParOr_pre',
    Thread = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'CEU_THREADS_T __thread_id_'..me.n..';\n'
        cls.struct = cls.struct..SPC()..'s8*       __thread_st_'..me.n..';\n'
    end,
    Thread_pos = 'ParOr_pos',
}

AST.visit(F)
