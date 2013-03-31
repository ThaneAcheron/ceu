_OPTS.tp_word    = assert(tonumber(_OPTS.tp_word),
    'missing `--tp-word´ parameter')
_OPTS.tp_pointer = assert(tonumber(_OPTS.tp_pointer),
    'missing `--tp-pointer´ parameter')

_ENV = {
    clss  = {},     -- { [1]=cls, ... [cls]=0 }
    clss_ifc = {},
    clss_cls = {},

    calls = {},     -- { _printf=true, _myf=true, ... }
    ifcs  = {},     -- { [1]='A', [2]='B', A=0, B=1, ... }

    exts = {
        --[1]=ext1,         [ext1.id]=ext1.
        --[N-1]={_ASYNC},   [id]={},
        --[N]={_WCLOCK},    [id]={},
    },

    c = {
        void = 0,

        u8=1, u16=2, u32=4, u64=8,
        s8=1, s16=2, s32=4, s64=8,

        word     = _OPTS.tp_word,
        int      = _OPTS.tp_word,
        pointer  = _OPTS.tp_pointer,

        tceu_ncls = true,    -- env.lua

        tceu_nlbl  = true,    -- labels.lua
        tceu_trail = true,    -- labels.lua (TODO: remove this type?)
    },
    dets  = {},
}

for k, v in pairs(_ENV.c) do
    if v == true then
        _ENV.c[k] = { tag='type', id=k, len=nil }
    else
        _ENV.c[k] = { tag='type', id=k, len=v }
    end
end

function CLS ()
    return _AST.iter'Dcl_cls'()
end

function var2ifc (var)
    return table.concat({
        var.id,
        var.tp,
        tostring(var.pre),
        tostring(var.arr),
    }, '$')
end

function _ENV.ifc_vs_cls (ifc, cls)
    -- check if they have been checked
    ifc.matches = ifc.matches or {}
    if ifc.matches[cls] ~= nil then
        return ifc.matches[cls]
    end

    -- check if they match
    for _, v1 in ipairs(ifc.blk_ifc.vars) do
        v2 = cls.blk_ifc.vars[v1.id]
        if v2 then
            v2.id_ifc = v2.id_ifc or var2ifc(v2)
        end
        if (not v2) or (v1.id_ifc~=v2.id_ifc) then
            ifc.matches[cls] = false
            return false
        end
    end

    -- yes, they match
    ifc.matches[cls] = true
    return true
end

function newvar (me, blk, pre, tp, dim, id)
    for stmt in _AST.iter() do
        if stmt.tag == 'Async' then
            break
        elseif stmt.tag == 'Block' then
            for _, var in ipairs(stmt.vars) do
                --ASR(var.id~=id or var.blk~=blk, me,
                    --'variable/event "'..var.id..
                    --'" is already declared at --line '..var.ln)
                WRN(var.id~=id, me,
                    'declaration of "'..id..'" hides the one at line '..var.ln)
            end
        end
    end

    local tp_raw = _TP.noptr(tp)
    local c = _ENV.c[tp_raw]
    local isEvt = (pre == 'event')

    ASR(_ENV.clss[tp_raw] or (c and c.tag=='type'),
        me, 'undeclared type `'..tp_raw..'´')
    ASR(not _ENV.clss_ifc[tp], me,
        'cannot instantiate an interface')
    ASR(_TP.deref(tp) or (not c) or (tp=='void' and isEvt) or c.len>0, me,
        'cannot instantiate type "'..tp..'"')
    ASR((not dim) or dim>0, me, 'invalid array dimension')

    tp = (dim and tp..'*') or tp

    local cls = _ENV.clss[tp] or (dim and _ENV.clss[_TP.deref(tp)])
    if cls then
        ASR(cls~=_AST.iter'Dcl_cls'() and isEvt==false, me,
                'invalid declaration')
    end

    local var = {
        ln    = me.ln,
        id    = id,
        cls   = cls,
        tp    = tp,
        blk   = blk,
        pre   = pre,
        inIfc = _AST.iter'BlockI'(),
        isEvt = isEvt,
        isTmp = false,
        arr   = dim,
        val   = '0',     -- TODO: workaround: dummy value for interfaces
    }
--DBG(var.id, var.isTmp)

    blk.vars[#blk.vars+1] = var
    blk.vars[id] = var -- TODO: last/first/error?
    -- TODO: warning in C (hides)

    return var
end

function _ENV.getvar (id, blk)
    while blk do
        for i=#blk.vars, 1, -1 do   -- n..1 (hidden vars)
            local var = blk.vars[i]
            if var.id == id then
                return var
            end
        end
        blk = blk.par
    end
end

-- identifiers for ID_c / ID_ext (allow to be defined after annotations)
-- variables for Var
function det2id (v)
    if type(v) == 'string' then
        return v
    else
        return v.var
    end
end

F = {
    Root_pre = function (me)
        local evt = {id='_FIN', pre='input'}
        _ENV.exts[#_ENV.exts+1] = evt
        _ENV.exts[evt.id] = evt

        local evt = {id='_ON', pre='input'}
        _ENV.exts[#_ENV.exts+1] = evt
        _ENV.exts[evt.id] = evt

        local evt = {id='_WCLOCK', pre='input'}
        _ENV.exts[#_ENV.exts+1] = evt
        _ENV.exts[evt.id] = evt

        local evt = {id='_ASYNC', pre='input'}
        _ENV.exts[#_ENV.exts+1] = evt
        _ENV.exts[evt.id] = evt
    end,

    Root = function (me)
        _ENV.c.tceu_ncls.len = _TP.n2bytes(#_ENV.clss_cls)

        -- matches all ifc vs cls
        for _, ifc in ipairs(_ENV.clss_ifc) do
            for _, cls in ipairs(_ENV.clss_cls) do
                _ENV.ifc_vs_cls(ifc, cls)
            end
        end
        local glb = _ENV.clss.Global
        if glb then
            ASR(glb.is_ifc and glb.matches[_ENV.clss.Main], me,
                'interface "Global" must be implemented by class "Main"')
        end
    end,

    Block_pre = function (me)
        me.vars = {}
        local async = _AST.iter()()
        if async.tag == 'Async' then
            local vars, blk = unpack(async)
            if vars then
                for _, n in ipairs(vars) do
                    local var = n.var
                    ASR(not var.arr, vars, 'invalid argument')
                    n.new = newvar(vars, blk, 'var', var.tp, nil, var.id)
                end
            end
        end
    end,
    Block = function (me)
        local orgs
        for _, var in ipairs(me.vars) do
            if var.cls then
                if not orgs then
                    orgs = _AST.node('Orgs')(me.ln)
                    orgs.vars = {}
                end
                orgs.vars[#orgs.vars+1] = var
            end
        end
        if orgs then
             -- run constructors first
            me[1] = _AST.node('ParOr')(me.ln, me[1], orgs)
        end
    end,

    Dcl_cls_pre = function (me)
        local ifc, id, blk = unpack(me)
        me.is_ifc = ifc
        me.id     = id
        me.glbs   = {}
        if id == 'Main' then
            _MAIN = me
        end
        ASR(not _ENV.clss[id], me,
                'interface/class "'..id..'" is already declared')

        _ENV.clss[id] = me
        _ENV.clss[#_ENV.clss+1] = me

        if me.is_ifc then
            _ENV.clss_ifc[id] = me
            _ENV.clss_ifc[#_ENV.clss_ifc+1] = me
        else
            me.n = #_ENV.clss_cls   -- TODO: remove Main?
            _ENV.clss_cls[id] = me
            _ENV.clss_cls[#_ENV.clss_cls+1] = me
        end
    end,
    Dcl_cls = function (me)
        -- expose each field
        if me.is_ifc then
            for _, var in pairs(me.blk_ifc.vars) do
                var.id_ifc = var.id_ifc or var2ifc(var)
                if not _ENV.ifcs[var.id_ifc] then
                    _ENV.ifcs[var.id_ifc] = #_ENV.ifcs
                    _ENV.ifcs[#_ENV.ifcs+1] = var.id_ifc
                end
            end
        end
    end,

    Dcl_det = function (me)                 -- TODO: verify in _ENV.c
        local id1 = det2id(me[1])
        local t1 = _ENV.dets[id1] or {}
        _ENV.dets[id1] = t1
        for i=2, #me do
            local id2 = det2id(me[i])
            local t2 = _ENV.dets[id2] or {}
            _ENV.dets[id2] = t2
            t1[id2] = true
            t2[id1] = true
        end
    end,

    Global = function (me)
        ASR(_ENV.clss.Global and _ENV.clss.Global.is_ifc, me,
            'interface "Global" is not defined')
        me.tp   = 'Global*'
        me.lval = false
        me.ref  = me
        me.fst  = me
        me.blk  = true --_MAIN.blk
    end,

    This = function (me)
        ASR(CLS() ~= _MAIN, me, 'invalid access')
        me.tp   = CLS().id
        me.lval = false
        me.ref  = me
        me.fst  = me
        me.blk  = CLS().blk_ifc
    end,

    Free = function (me)
        local exp = unpack(me)
        local _tp = _TP.deref(exp.tp)
        ASR(_tp and _ENV.clss[_tp], me, 'invalid `free´')
    end,

    Dcl_ext = function (me)
        local dir, tp, id = unpack(me)
        ASR(not _ENV.exts[id], me, 'event "'..id..'" is already declared')
        ASR(tp=='void' or tp=='int' or _TP.deref(tp),
                me, 'invalid event type')

        me.evt = {
            ln    = me.ln,
            id    = id,
            tp    = tp,
            pre   = dir,
            isEvt = true,
        }
        _ENV.exts[#_ENV.exts+1] = me.evt
        _ENV.exts[id] = me.evt
    end,

    Dcl_int = 'Dcl_var',
    Dcl_var = function (me)
        local pre, tp, dim, id = unpack(me)
        ASR((not dim) or tonumber(dim.sval), me, 'invalid static expression')
        if pre == 'event' then
            ASR(tp=='void' or tp=='int' or _TP.deref(tp),
                    me, 'invalid event type')
        end
        me.var = newvar(me, _AST.iter'Block'(), pre, tp, dim and dim.sval, id)
        me.var.read_only = me.read_only

--[=[
-- TODO: remove!
        local cls = me.var.cls or
                    me.var.arr and _ENV.clss[_TP.deref(me.var.tp)]
        if cls then
            local blk = CLS().blk_body
            cls.glbs = ((not blk) or _AST.iter'Block'().depth<=blk.depth)
                        and cls.glbs
            if cls.glbs then
                cls.glbs[#cls.glbs+1] = me.var
            end
        end
]=]
    end,

    Dcl_imp = function (me)
        local id = unpack(me)
        local cls = ASR(_ENV.clss[id], me,
                        'class "'..id..'" is not declared')
        for _, var in ipairs(cls.blk_ifc.vars) do
            local tp = (var.dim and _TP.deref(var.tp)) or var.tp
            newvar(me, _AST.iter'Block'(), var.pre, tp, var.arr, var.id)
        end
    end,

    Ext = function (me)
        local id = unpack(me)
        me.evt = ASR(_ENV.exts[id], me,
                    'event "'..id..'" is not declared')
    end,

    Var = function (me)
        local id = unpack(me)
        local blk = me.blk or _AST.iter('Block')()
        local var = _ENV.getvar(id, blk)
        ASR(var, me, 'variable/event "'..id..'" is not declared')
        me.var  = var
        me.tp   = var.tp
        me.lval = (not var.arr) and (not var.cls)
        me.ref  = me
        me.fst  = var
        if var.isEvt then
            me.evt = var
        end
    end,

    Dcl_c = function (me)
        local mod, tag, id, len = unpack(me)
        len = ASR((not len) or len.sval, me, 'invalid static expression')
        if _AST.iter'BlockI'() then
            local cls = CLS()
            id = ((cls.is_ifc and 'IFC_') or 'CLS_')..cls.id..'_'..id
        end
        _ENV.c[id] = { tag=tag, id=id, len=len, mod=mod }
    end,

    Dcl_pure = function (me)
        _ENV.pures[me[1]] = true
    end,

    AwaitS = function (me)
        local wclock
        for _, awt in ipairs(me) do
            if awt.isExp then
                F.AwaitInt(me, awt)
            elseif awt.tag~='Ext' then
                ASR(not wclock, me,
                    'invalid await: multiple timers')
                wclock = true
            end
        end
    end,
    AwaitInt = function (me, exp)
        local exp = exp or unpack(me)
        local var = exp.var
        ASR(var and var.isEvt, me,
                'event "'..(var and var.id or '?')..'" is not declared')
    end,

    EmitInt = function (me)
        local e1, e2 = unpack(me)
        local var = e1.var
        ASR(var and var.isEvt, me,
                'event "'..(var and var.id or '?')..'" is not declared')
        ASR(((not e2) or _TP.contains(e1.var.tp,e2.tp,true)),
                me, 'invalid emit')
    end,

    EmitExtS = function (me)
        local e1, _ = unpack(me)
        if e1.evt.pre == 'output' then
            F.EmitExtE(me)
        end
    end,
    EmitExtE = function (me)
        local e1, e2 = unpack(me)
        ASR(e1.evt.pre == 'output', me, 'invalid input `emit´')
        me.tp = 'int'

        if e2 then
            ASR(_TP.contains(e1.evt.tp,e2.tp,true),
                    me, "non-matching types on `emit´")
        else
            ASR(e1.evt.tp=='void',
                    me, "missing parameters on `emit´")
        end
    end,

    --------------------------------------------------------------------------

    SetExp = function (me)
        local e1, e2, op = unpack(me)
        e1 = e1 or _AST.iter'SetBlock'()[1]
        ASR(e1.lval and _TP.contains(e1.tp,e2.tp,true),
                me, 'invalid attribution')

        ASR(me.read_only or (not e1.fst.read_only),
                me, 'read-only variable')

        if op == ':=' then
           -- ensures that `:=´ is used correctly (not lval == &ref)
            local _tp2 = _TP.deref(e2.tp)
            ASR(_tp2 and _ENV.clss[_tp2] and e2.lval,
                    me, 'invalid attribution')
            return
        end

        local req = false

        if _TP.deref(e1.tp) then
            local blk1 = (e1.fst=='_' and _AST.root) or e1.fst.blk
            if e2.fst and e2.fst~='_' then
                local blk2 = e2.fst.blk
                if blk2 then
                    local d1 = (blk1==true and 0) or blk1.depth
                    local d2 = (blk2==true and 0) or blk2.depth

                    -- int a; pa=&a;    -- `a´ termination must consider `pa´
                    req = d2 > d1 and (
                            blk1 == true or             -- `pa´ global
                            d2 > CLS().blk_body.depth   -- `a´ not top-level
                    )
                end
                req = req and blk2
            else
                -- int* pa = _fopen();  -- `pa´ termination must consider ret
                req = (e2.tag=='Op2_call' and e2.c.mod~='pure')
                req = req and blk1
            end
        end
        ASR((not req) or me.fin, me, 'attribution requires `finalize´')
        ASR((not me.fin) or req, me, 'invalid `finalize´')

        if me.fin and me.fin.active then
            req.fins = req.fins or {}
            table.insert(req.fins, 1, me.fin)
        end
    end,

    Op2_call_pre = function (me)
        local _, f, exps, fin = unpack(me)
        if fin then
            F.Finalize_pre(me, me, fin)
        end
    end,
    Finalize_pre = function (me, set, fin)
        if not fin then
            set, fin = unpack(me)
        end
        assert(fin[1].tag == 'Block')
        assert(fin[1][1].tag == 'Stmts')
        fin.active = fin[1] and fin[1][1] and
                        (#fin[1][1]>1 or
                         fin[1][1][1] and fin[1][1][1].tag~='Nothing')
        if set then
            set.fin = fin                   -- let call/set handle
        elseif fin.active then
            local blk = _AST.iter'Block'()
            blk.fins = blk.fins or {}
            table.insert(blk.fins, 1, fin)  -- force finalize for this blk
        end
    end,

    SetAwait = function (me)
        local e1, awt = unpack(me)
        ASR(e1.lval, me, 'invalid attribution')

        if awt.tag == 'Loop' then
            awt = awt[1][1]         -- await ... until
        end
        me.awt = awt                -- will need me.awt.val

        if awt.tag == 'AwaitT' then
            ASR(_TP.isNumeric(e1.tp,true), me, 'invalid attribution')
        elseif awt.tag == 'AwaitS' then
            ASR(_TP.isNumeric(e1.tp,true), me, 'invalid attribution')
        else    -- AwaitInt / AwaitExt
            local evt = awt[1].evt
            ASR(_TP.contains(e1.tp,evt.tp,true), me, 'invalid attribution')
        end
    end,

    SetNew = function (me)
        local exp, id_cls = unpack(me)
        me.cls = ASR(_ENV.clss[id_cls], me,
                        'class "'..id_cls..'" is not declared')
        ASR(not me.cls.is_ifc, me, 'cannot instantiate an interface')
        ASR(exp.lval and _TP.contains(exp.tp,me.cls.id..'*'),
                me, 'invalid attribution')
    end,

    CallStmt = function (me)
        local call = unpack(me)
        ASR(call.tag == 'Op2_call', me, 'invalid statement')
    end,

    --------------------------------------------------------------------------

    Op2_call = function (me)
        local _, f, exps, fin = unpack(me)
        me.tp  = '_'
        me.fst = '_'
        local id
        if f.tag == 'C' then
            id   = f[1]
            me.c = _ENV.c[id]
        elseif f.tag == 'Op2_.' then
            id   = f.id
            me.c = f.c
        else
            id = '$anon'
            me.c = { tag='func', id=id, mod=nil }
        end

        ASR((not _OPTS.c_calls) or _OPTS.c_calls[id],
            me, 'C calls are disabled')

        ASR(me.c and me.c.tag=='func', me,
            'C function "'..id..'" is not declared')

        _ENV.calls[id] = true

        local req = false

        if not (me.c and (me.c.mod=='pure' or me.c.mod=='nohold')) then
            if f.org then
                exps = { f.org, unpack(exps) }
            end
            for _, exp in ipairs(exps) do
                -- int* pa; _f(pa); -- `pa´ termination must consider `_f´
                local r = exp.fst and (
                             _TP.deref(exp.tp)
                          or (_TP.ext(exp.tp) and (not exp.c or
                                                   exp.c.mod~='constant'))
                          or _ENV.clss[_TP.noptr(exp.tp)])
                r = r and ((exp.fst=='_' and _AST.root) or exp.fst.blk)
                WRN( (not r) or (not req) or (r==req),
                        me, 'invalid call (multiple scopes)')
                req = req or r
            end
        end

        ASR((not req) or fin, me, 'call requires `finalize´')
        ASR((not fin) or req, me, 'invalid `finalize´')

        if fin and fin.active then
            req.fins = req.fins or {}
            table.insert(req.fins, 1, fin)
        end
    end,

    Op2_idx = function (me)
        local _, arr, idx = unpack(me)
        local tp = ASR(_TP.deref(arr.tp,true), me, 'cannot index a non array')
        ASR(tp and _TP.isNumeric(idx.tp,true), me, 'invalid array index')
        me.tp = tp
--DBG('idx', arr.tag, arr.lval)
        me.lval = (not _ENV.clss[tp])
        me.ref  = arr.ref
        me.fst  = arr.fst
    end,

    Op2_int_int = function (me)
        local op, e1, e2 = unpack(me)
        me.tp  = 'int'
        ASR(_TP.isNumeric(e1.tp,true) and _TP.isNumeric(e2.tp,true),
            me, 'invalid operands to binary "'..op..'"')

        if e1.sval and e2.sval then
            local v = loadstring('return '..e1.sval..op..e2.sval)
            me.sval = v and tonumber(v())
        end
    end,
    ['Op2_-']  = 'Op2_int_int',
    ['Op2_+']  = 'Op2_int_int',
    ['Op2_%']  = 'Op2_int_int',
    ['Op2_*']  = 'Op2_int_int',
    ['Op2_/']  = 'Op2_int_int',
    ['Op2_|']  = 'Op2_int_int',
    ['Op2_&']  = 'Op2_int_int',
    ['Op2_<<'] = 'Op2_int_int',
    ['Op2_>>'] = 'Op2_int_int',
    ['Op2_^']  = 'Op2_int_int',

    Op1_int = function (me)
        local op, e1 = unpack(me)
        me.tp  = 'int'
        ASR(_TP.isNumeric(e1.tp,true),
                me, 'invalid operand to unary "'..op..'"')
        if e1.sval then
            local v = loadstring(op..e1.sval)
            me.sval = v and tonumber(v())
        end
    end,
    ['Op1_~']  = 'Op1_int',
    ['Op1_-']  = 'Op1_int',

    Op2_same = function (me)
        local op, e1, e2 = unpack(me)
        me.tp  = 'int'
        ASR(_TP.max(e1.tp,e2.tp,true),
                me, 'invalid operands to binary "'..op..'"')
    end,
    ['Op2_=='] = 'Op2_same',
    ['Op2_!='] = 'Op2_same',
    ['Op2_>='] = 'Op2_same',
    ['Op2_<='] = 'Op2_same',
    ['Op2_>']  = 'Op2_same',
    ['Op2_<']  = 'Op2_same',

    Op2_any = function (me)
        me.tp  = 'int'
    end,
    ['Op2_or']  = 'Op2_any',
    ['Op2_and'] = 'Op2_any',
    ['Op1_not'] = 'Op2_any',

    ['Op1_*'] = function (me)
        local op, e1 = unpack(me)
        me.tp   = _TP.deref(e1.tp, true)
        me.lval = e1.lval
        me.ref  = e1.ref
        me.fst  = e1.fst
        ASR(me.tp, me, 'invalid operand to unary "*"')
    end,

    ['Op1_&'] = function (me)
        local op, e1 = unpack(me)
        ASR(_ENV.clss[e1.tp] or e1.lval, me, 'invalid operand to unary "&"')
        me.tp   = e1.tp..'*'
        me.lval = false
        me.ref  = e1.ref
        me.fst  = e1.fst
    end,

    ['Op2_.'] = function (me)
        local op, e1, id = unpack(me)
        local cls = _ENV.clss[e1.tp]
        me.id = id
        if cls then
            me.org = e1

            if string.sub(id,1,1)=='_' then
                local id = ((cls.is_ifc and 'IFC_') or 'CLS_')..cls.id..'_'..id
                local c = _ENV.c[id]
                ASR(c and c.tag=='func', me,
                        'C function "'..id..'" is not declared')
                me[3] = _AST.node('C')(me.ln, id)
                me.c    = c
                me.tp   = '_'
                me.lval = false
                me.ref  = me[3]
            else
                local var = ASR(cls.blk_ifc.vars[id], me,
                            'variable/event "'..id..'" is not declared')
                me[3] = _AST.node('Var')(me.ln)
                me[3].var = var

                me.org  = e1
                me.var  = var
                me.tp   = var.tp
                me.lval = (not var.arr) and (not var.cls)
                me.ref  = me[3]
                if var.isEvt then
                    me.evt    = me.var
                    me[3].evt = var
                end
            end
        else
            ASR(_TP.ext(e1.tp,true), me, 'not a struct')
            me.tp   = '_'
            me.lval = e1.lval
            me.ref  = e1.ref
        end
        me.fst = e1.fst
    end,

    Op1_cast = function (me)
        local tp, exp = unpack(me)
        me.tp   = tp
        me.lval = exp.lval
        me.ref  = exp.ref
        me.fst  = exp.fst
    end,

    C = function (me)
        local id = unpack(me)
        local c = _ENV.c[id]
        ASR(c and (c.tag=='var' or c.tag=='func'), me,
            'C variable/function "'..id..'" is not declared')
        me.tp   = '_'
        me.lval = true
        me.ref  = me
        me.fst  = '_'
        me.c    = c
    end,

    WCLOCKK = function (me)
        me.tp   = 'int'
        me.lval = false
        me.fst  = false
    end,
    WCLOCKE = 'WCLOCKK',

    SIZEOF = function (me)
        me.tp   = 'int'
        me.lval = false
        me.fst  = false

        local tp = unpack(me)
        local sz = 0
        for _,tp in ipairs(me) do
            local t = _TP.deref(tp) and _ENV.c.pointer or _ENV.c[tp]
            local i = ASR(t and t.len, me, 'undeclared type '..tp)
            sz = _TP.align(sz,i) + i
        end
        me.sval = sz
    end,

    STRING = function (me)
        me.tp   = '_char*'
        me.lval = false
        me.fst  = false
    end,
    CONST = function (me)
        local v = unpack(me)
        me.tp   = 'int'
        me.lval = false
        me.fst  = false
        me.sval = tonumber(v)
        ASR(string.sub(v,1,1)=="'" or tonumber(v), me, 'malformed number')
    end,
    NULL = function (me)
        me.tp   = 'void*'
        me.lval = false
        me.fst  = false
    end,
}

_AST.visit(F)
