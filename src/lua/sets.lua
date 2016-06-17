F = {
    __check = function (me, to_tp, fr_tp)
        if TYPES.check(to_tp,'?') then
            to_tp = TYPES.pop(to_tp)
        end
        ASR(TYPES.contains(to_tp,fr_tp), me,
            'invalid assignment : types mismatch : "'..TYPES.tostring(to_tp)..
                                                        '" <= "'..
                                                       TYPES.tostring(fr_tp)..
                                                        '"')
    end,

    Set_Exp = function (me)
        local fr, to = unpack(me)
        F.__check(me, to.tp, fr.tp)
    end,

    Set_Await_one = function (me)
        local fr, to = unpack(me)
        assert(fr.tag=='Await_Wclock' or fr.tag=='Await_Code' or fr.tag=='Await_Evt')
        F.__check(me, to.tp, fr.tp)
    end,

    Set_Await_many = function (me)
        local fr, to = unpack(me)
        local awt = unpack(AST.asr(fr,'Await_Until'))
        F.__check(me, to.tp, awt.tp)
    end,
    Await_Ext = function (me)
        local ID_ext = unpack(me)
        me.tp = AST.copy(ID_ext.tp)
    end,
    Await_Evt = function (me)
        local e = unpack(me)
        me.tp = AST.copy(e.tp)
    end,
    Await_Wclock = function (me)
        me.tp = TYPES.new(me, 'int')
    end,
    Await_Code = function (me)
        local ID_abs = AST.asr(unpack(me),'ID_abs')
        local Type = AST.asr(ID_abs.top,'Code_impl', 5,'Type')
        me.tp = AST.copy(Type)
    end,

    Set_Emit_Ext_emit = function (me)
        local ID_ext = unpack(AST.asr(me,'', 1,'Emit_Ext_emit'))
        local _,io = unpack(AST.asr(ID_ext.top,'Ext'))
        ASR(io=='output', me,
            'invalid assignment : `input´')
    end,
}
AST.visit(F)
