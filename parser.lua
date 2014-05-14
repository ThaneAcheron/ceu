local P, C, V, Cc, Ct = m.P, m.C, m.V, m.Cc, m.Ct

local S = V'__SPACES'

local ERR_msg
local ERR_i
local LST_i

local I2TK

local f = function (s, i, tk)
    if tk == '' then
        tk = '<BOF>'
        LST_i = 1           -- restart parsing
        ERR_i = 0           -- ERR_i < 1st i
        ERR_msg = '?'
        I2TK = { [1]='<BOF>' }
    elseif i > LST_i then
        LST_i = i
        I2TK[i] = tk
    end
    return true
end
local K = function (patt, key)
    key = key and -m.R('09','__','az','AZ','\127\255')
            or P(true)
    ERR_msg = '?'
    return #P(1) * m.Cmt(patt*key, f) * S
end
local CK = function (patt, key)
    key = key and -m.R('09','__','az','AZ','\127\255')
            or P(true)
    ERR_msg = '?'
    return C(m.Cmt(patt*key, f))*S
end
local EK = function (tk, key)
    key = key and -m.R('09','__','az','AZ','\127\255')
            or P(true)
    return K(P(tk)*key) + m.Cmt(P'',
        function (_,i)
            if i > ERR_i then
                ERR_i = i
                ERR_msg = 'expected `'..tk.."´"
            end
            return false
        end) * P(false)
end

local KEY = function (str)
    return K(str,true)
end
local EKEY = function (str)
    return EK(str,true)
end
local CKEY = function (str)
    return CK(str,true)
end

local _V2NAME = {
    __Exp = 'expression',
    _Stmt = 'statement',
    Ext = 'event',
    Var = 'variable/event',
    __ID_nat  = 'identifier',
    __ID_var  = 'identifier',
    __ID_ext  = 'identifier',
    __ID_cls  = 'identifier',
    __ID_type = 'type',
    __ID_field = 'identifier',
    __Dcl_var = 'declaration',
    _Dcl_int = 'declaration',
    _Dcl_pool = 'declaration',
    __Dcl_nat  = 'declaration',
    _Dcl_nat   = 'declaration',
    TupleType = 'type list',
}
local EV = function (rule)
    return V(rule) + m.Cmt(P'',
        function (_,i)
            if i > ERR_i then
                ERR_i = i
                ERR_msg = 'expected ' .. _V2NAME[rule]
            end
            return false
        end) * P(false)
end

local EM = function (msg)
    return m.Cmt(P'',
        function (_,i)
            if i > ERR_i then
                ERR_i = i
                ERR_msg = 'expected ' .. msg
                return false
            end
            return true
        end)
end

TYPES = P'void' + 'char' + 'byte' + 'bool' + 'word'
      + 'int' + 'uint'
      + 'u8' + 'u16' + 'u32' + 'u64'
      + 's8' + 's16' + 's32' + 's64'
      + 'float' + 'f32' + 'f64'

KEYS = P'and'     + 'async'    + 'await'    + 'break'    + 'native'
     + 'constant' + 'continue' + 'safe'     + 'do'
     + 'else'     + 'else/if'  + 'emit'     + 'end'      + 'event'
     + 'every'    + 'finalize' + 'FOREVER'  + 'if'       + 'input'
     + 'loop'     + 'nohold'   + 'not'      + 'nothing'  + 'null'
     + 'or'       + 'output'   + 'par'      + 'par/and'  + 'par/or'
     + 'pause/if' + 'pure'     + 'escape'   + 'sizeof'   + 'then'
     + 'until'    + 'var'      + 'with'
     + TYPES
-- ceu-orgs only
     + 'class'    + 'global'   + 'interface'
     + 'free'     + 'new'      + 'this'
     + 'spawn'
--
     --+ 'import'  --+ 'as'
-- export / version
     + 'thread'   + 'sync'
-- functions
     + 'function' + 'call' + 'return' + 'recursive' + 'call/rec'
     + 'hold'
-- isrs
     + 'isr' + 'atomic'
-- bool
     + 'true' + 'false'
-- requests
     + 'input/output' + 'output/input'
-- time
     --+ 'h' + 'min' + 's' + 'ms' + 'us'
-- loop/every
     + 'in'
-- pool
     + 'pool'
     + 'watching'
--
     + 'plain'

KEYS = KEYS * -m.R('09','__','az','AZ','\127\255')

local Alpha    = m.R'az' + '_' + m.R'AZ'
local Alphanum = Alpha + m.R'09'
local ALPHANUM = m.R'AZ' + '_' + m.R'09'
local alphanum = m.R'az' + '_' + m.R'09'

NUM = CK(m.R'09'^1) / tonumber

_GG = { [1] = CK'' * V'_Stmts' * P(-1)-- + EM'expected EOF')

                -- "Ct" as a special case to avoid "too many captures" (HACK_1)
    , _Stmts  = Ct (( V'__StmtS' * (EK';'*K';'^0) +
                      V'__StmtB' * (K';'^0)
                   )^0
                 * ( V'__LstStmt' * (EK';'*K';'^0) +
                     V'__LstStmtB' * (K';'^0)
                   )^-1 )
    , Block  = V'_Stmts'

    , Do     = V'__Do'
    , __Do    = KEY'do' * V'Block' * KEY'end'

    , Nothing = KEY'nothing'

    , __StmtS = V'AwaitS'   + V'AwaitT'    + V'AwaitExt'  + V'AwaitInt'
             + V'EmitT'    + V'EmitExt'   + V'EmitInt'
             + V'_Dcl_nat' + V'_Dcl_ext0'
             + V'_Dcl_int' + V'__Dcl_var' + V'_Dcl_pool'
             + V'Dcl_det'
             --+ V'Call'
             + V'_Set_constr'   -- must be before "_Set"
             + V'_Set'
             + V'Spawn'    --+ V'Free'
             + V'Nothing'
             + V'RawStmt'
             --+ V'Import'
             + V'_Dcl_fun0'
             + V'CallStmt' -- last
             --+ EM'statement'-- (missing `_´?)'
             + EM'statement (usually a missing `var´ or C prefix `_´)'

    , __StmtB = V'Do'    + V'Host'
             + V'Async' + V'_Thread' + V'Sync' + V'Atomic'
             + V'ParOr' + V'ParAnd'  + V'_Watching'
             + V'If'    + V'_Loop'   + V'_Every'  + V'_Iter'
             + V'_Pause'
             + V'_Dcl_ifc' + V'Dcl_cls'
             + V'Finalize'
             + V'_Dcl_fun1' + V'_Dcl_ext1'

    , __LstStmt  = V'_Escape' + V'Break' + V'_Continue' + V'AwaitN' + V'Return'
    , __LstStmtB = V'ParEver' + V'_Continue'

    , __SetBlock  = V'Do' + V'ParEver' + V'If' + V'_Loop' + V'_Every'

    , VarList = ( K'(' * EV'Var' * (EK',' * EV'Var')^0 * EK')' )

    , _Set  = (V'__Exp' + V'VarList') * V'__Sets'
    , __Sets = (CK'='+CK':=') * (
                                    -- p1=awt, p2=false, p3=false
                Cc'__SetAwait'   * (V'AwaitS'+V'AwaitT'+V'AwaitExt'+V'AwaitInt')
                                 * Cc(false) * Cc(false)
                                    -- p1=blk, p2=false, p3=false
              + Cc'__SetThread'  * V'_Thread'
                                 * Cc(false) * Cc(false)
                                    -- p1=blk, p2=false, p3=false
              + Cc'__SetEmitExt' * ( V'EmitExt'
                                   + K'(' * V'EmitExt' * EK')' )
                                    -- p1=emt, p2=false, p3=false
              + Cc'__SetNew'     * V'New'
                                    -- p1=Spawn[max,cls,constr]
              + Cc'__SetSpawn'   * V'Spawn'
              + Cc'SetBlock'     * V'__SetBlock'
                                 * Cc(false) * Cc(false)
                                    -- p1=[list,blk]
              + Cc'SetExp'       * V'__Exp'
                                 * Cc(false) * Cc(false)
                                    -- p1=New[max,cls,constr]
              + EM'expression'
              )

    , Finalize = KEY'finalize' * (V'_Set'*EK';'*K';'^0 + Cc(false))
               * EKEY'with' * EV'Finally' * EKEY'end'
    , Finally  = V'Block'

    , Free  = KEY'free'  * V'__Exp'
    , New   = KEY'new'   * EV'__ID_cls' * (KEY'in'*EV'__Exp' + Cc(false))
            * (EKEY'with'*V'Dcl_constr'*EKEY'end' + Cc(false))
    , Spawn = KEY'spawn' * EV'__ID_cls' * (KEY'in'*EV'__Exp' + Cc(false))
            * (EKEY'with'*V'Dcl_constr'* EKEY'end' + Cc(false))

    , CallStmt = m.Cmt(V'__Exp',
                    function (s,i,...)
                        return (string.find(s, '%(.*%)')) and i, ...
                    end)

    , Atomic  = KEY'atomic' * V'__Do'
    , Sync    = KEY'sync'   * V'__Do'
    , _Thread = KEY'async' * KEY'thread'    * (V'RefVarList'+Cc(false)) * V'__Do'
    , Async   = KEY'async' * (-P'thread') * (V'RefVarList'+Cc(false)) * V'__Do'

    , __var      = (CK'&'+Cc(false)) * EV'Var'
    , RefVarList = ( K'(' * EV'__var' * (EK',' * EV'__var')^0 * EK')' )

    , _Escape = KEY'escape' * EV'__Exp'

    , _Watching = KEY'watching' * EV'__awaits' * EKEY'do' * V'Block' * EKEY'end'
    , ParOr     = KEY'par/or' * EKEY'do' *
                      V'Block' * (EKEY'with' * V'Block')^1 *
                  EKEY'end'

    , ParAnd  = KEY'par/and' * EKEY'do' *
                    V'Block' * (EKEY'with' * V'Block')^1 *
                EKEY'end'
    , ParEver = KEY'par' * EKEY'do' *
                    V'Block' * (EKEY'with' * V'Block')^1 *
                EKEY'end'

    , If      = KEY'if' * EV'__Exp' * EKEY'then' *
                    V'Block' *
                (KEY'else/if' * EV'__Exp' * EKEY'then' *
                    V'Block')^0 *
                (KEY'else' *
                    V'Block' + Cc(false)) *
                EKEY'end'-- - V'_Continue'

    , Break    = KEY'break'
    , _Continue = KEY'continue'

    , _Loop    = KEY'loop' *
                    (V'__ID_var' * (EKEY'in'*EV'__Exp' + Cc(false)) +
                        Cc(false)*Cc(false)) *
                V'__Do'

    , _Iter   = KEY'loop' * K'('*EV'__ID_type'*EK')'
              *     V'__ID_var' * KEY'in' * EV'__Exp'
              * V'__Do'

    , _Every  = KEY'every' * ( (EV'__Exp'+V'VarList') * EKEY'in'
                            + Cc(false) )
              *  (V'WCLOCKK' + V'WCLOCKE' + EV'Ext' + EV'__Exp')
              * V'__Do'

    , __Exp    = V'__1'
    , __1      = V'__2'  * (CKEY'or'  * V'__2')^0
    , __2      = V'__3'  * (CKEY'and' * V'__3')^0
    , __3      = V'__4'  * ((CK'|'-'||') * V'__4')^0
    , __4      = V'__5'  * (CK'^' * V'__5')^0
    , __5      = V'__6'  * (CK'&' * V'__6')^0
    , __6      = V'__7'  * ((CK'!='+CK'==') * V'__7')^0
    , __7      = V'__8'  * ((CK'<='+CK'>='+(CK'<'-'<<')+(CK'>'-'>>')) * V'__8')^0
    , __8      = V'__9'  * ((CK'>>'+CK'<<') * V'__9')^0
    , __9      = V'__10' * ((CK'+'+CK'-') * V'__10')^0
    , __10     = V'__11' * ((CK'*'+(CK'/'-'//'-'/*')+CK'%') * V'__11')^0
    , __11     = ( Cc(false) * (CKEY'not'+CK'&'+CK'-'+CK'+'+ CK'~'+CK'*'
                             + Cc'cast'*(K'('*V'__ID_type'*K')') )
                )^0 * V'__12'
    , __12     = V'__13' *
                    (
                        K'(' * Cc'call' * V'ExpList' * EK')' *
                            ( KEY'finalize' * EKEY'with' * V'Finally' * EKEY'end'
                              + Cc(false)) +
                        K'[' * Cc'idx'  * V'__Exp'    * EK']' +
                        (CK':' + CK'.') * EV'__ID_field'
                    )^0
    , __13     = V'__Prim'
    , __Prim   = V'__Parens' + V'SIZEOF'
              + V'Var'     + V'Nat'
              + V'NULL'    + V'NUMBER' + V'STRING'
              + V'Global'  + V'This'   + V'RawExp'
              + CKEY'call'     * EV'__Exp'
              + CKEY'call/rec' * EV'__Exp'

    , ExpList = ( V'__Exp'*(K','*EV'__Exp')^0 )^-1

    , __Parens  = K'(' * EV'__Exp' * EK')'

    , SIZEOF = KEY'sizeof' * EK'(' * (V'__ID_type' + V'__Exp') * EK')'

    , NUMBER = CK( #m.R'09' * (m.R'09'+m.S'xX'+m.R'AF'+m.R'af'+'.'
                                      +(m.S'Ee'*'-')+m.S'Ee')^1 )
            + CK( "'" * (P(1)-"'")^0 * "'" )
            + KEY'false' / function() return 0 end
            + KEY'true'  / function() return 1 end

    , NULL = CKEY'null'

    , WCLOCKK = #NUM *
                (NUM * K'h'   + Cc(0)) *
                (NUM * K'min' + Cc(0)) *
                (NUM * K's'   + Cc(0)) *
                (NUM * K'ms'  + Cc(0)) *
                (NUM * K'us'  + Cc(0)) *
                (NUM * EM'<h,min,s,ms,us>')^-1
    , WCLOCKE = K'(' * V'__Exp' * EK')' * (
                    CK'h' + CK'min' + CK's' + CK'ms' + CK'us'
                  + EM'<h,min,s,ms,us>'
              )

    , _Pause   = KEY'pause/if' * EV'__Exp' * V'__Do'

    , AwaitN   = KEY'await' * KEY'FOREVER'

    , __until  = KEY'until' * EV'__Exp'
    , AwaitExt = KEY'await' * EV'Ext'  * (V'__until' + Cc(false))
    , AwaitInt = KEY'await' * EV'__Exp' * (V'__until' + Cc(false))
    , AwaitT   = KEY'await' * (V'WCLOCKK'+V'WCLOCKE')
                                     * (V'__until' + Cc(false))

    , __awaits = (V'WCLOCKK' + V'WCLOCKE' + V'Ext' + EV'__Exp')
    , ___awaits = K'(' * V'__awaits' * EK')'
    , AwaitS   = KEY'await' * V'___awaits' * (EKEY'or' * V'___awaits')^1
                                     * (V'__until' + Cc(false))

    , EmitT    = KEY'emit' * (V'WCLOCKK'+V'WCLOCKE')

    , EmitExt  = (CKEY'call/rec'+CKEY'call'+CKEY'emit'+CKEY'request')
               * EV'Ext' * V'__emit_ps'
    , EmitInt  = CKEY'emit' * EV'__Exp' * V'__emit_ps'
    , __emit_ps = ( K'=>' * (V'__Exp' + K'(' * V'ExpList' * EK')')
                +   Cc(false) )

    , __ID     = V'__ID_nat' + V'__ID_ext' + V'Var'
    , Dcl_det  = KEY'safe' * EV'__ID' * EKEY'with' *
                     EV'__ID' * (K',' * EV'__ID')^0

    , __Dcl_nat = Cc'type' * V'__ID_nat' * K'=' * NUM
                + Cc'func' * V'__ID_nat' * '()' * Cc(false)
                + Cc'unk'  * V'__ID_nat'        * Cc(false)

    , _Dcl_nat = KEY'native' * (CKEY'pure'+CKEY'constant'+CKEY'nohold'+CK'plain'+Cc(false))
                   * EV'__Dcl_nat' * (K',' * EV'__Dcl_nat')^0

    , __Dcl_ext_call = (CKEY'input'+CKEY'output')
                     * (CKEY'recursive'+Cc(false))
                     * V'TupleType' * K'=>' * EV'__ID_type'
                     * Cc(false)     -- spawn array
                     * EV'__ID_ext' * (K','*EV'__ID_ext')^0
    , __Dcl_ext_evt  = (CKEY'input'+CKEY'output')
                     * Cc(false)     -- recursive
                     * (V'TupleType'+EV'__ID_type') * Cc(false)
                     * Cc(false)     -- spawn array
                     * EV'__ID_ext' * (K','*EV'__ID_ext')^0
    , __Dcl_ext_io   = (CKEY'input/output'+CKEY'output/input')
                     * Cc(false)     -- recursive
                     * V'TupleType' * K'=>' * EV'__ID_type'
                     * ('['*NUM*EK']'+Cc(false))
                     * EV'__ID_ext' * (K','*EV'__ID_ext')^0

    , _Dcl_ext0 = V'__Dcl_ext_io' + V'__Dcl_ext_call' + V'__Dcl_ext_evt'
    , _Dcl_ext1 = V'_Dcl_ext0' * V'__Do'

    , _Dcl_int  = CKEY'event' * (V'TupleType'+EV'__ID_type') *
                    EV'__ID_var' * (K','*EV'__ID_var')^0

    , _Dcl_pool = CKEY'pool' * EV'__ID_cls' *
                    EK'[' * (V'__Exp' + Cc(false)) * EK']' *
                        EV'__ID_var' * (K','*EV'__ID_var')^0

    -------
    , __Dcl_var   = V'_Dcl_var_1' + V'_Dcl_var_2'

    -- w/o constructor
    , _Dcl_var_2 = CKEY'var'
                 * (EV'__ID_type' + EV'__ID_cls')
                 * (K'['*V'__Exp'*K']' + Cc(false))
                 * V'__dcl_var' * (K','*V'__dcl_var')^0

    -- w/  constructor
    , _Dcl_var_1 = CKEY'var'
                 * EV'__ID_cls'
                 * (K'['*V'__Exp'*K']' + Cc(false))
                 * EV'__ID_var'
                 * EKEY'with' * V'Dcl_constr' * EKEY'end'
    , Dcl_constr = V'_Stmts'     -- TODO: Block?
    , _Set_constr = KEY'_' * K'.' * EV'__ID_field' * (CK'='+CK':=') * V'__Exp'

    , __dcl_var = EV'__ID_var' * (V'__Sets' +
                                Cc(false)*Cc(false)*Cc(false)*Cc(false)*Cc(false))
    -------

    , _Dcl_imp = KEY'interface' * EV'__ID_cls' * (K',' * EV'__ID_cls')^0

    , _Dcl_fun0 = KEY'function' * CKEY'isr' * EK'[' * NUM * EK']' * (CKEY'recursive'+Cc(false))
                + CKEY'function' * (CKEY'recursive'+Cc(false))
                               * EV'TupleType' * EK'=>' * EV'__ID_type'
                               * V'__ID_var'

    , _Dcl_fun1 = V'_Dcl_fun0' * V'__Do'
    , Return  = KEY'return' * EV'__Exp'^-1

    , BlockI = ( (EV'__Dcl_var'+V'_Dcl_int'+V'_Dcl_pool'+V'_Dcl_fun0'+V'_Dcl_imp')
                  * (EK';'*K';'^0)
               )^0
    , _Dcl_ifc = KEY'interface' * Cc(true)
               * EV'__ID_cls'
               * EKEY'with' * V'BlockI' * EKEY'end'
    , Dcl_cls  = KEY'class'     * Cc(false)
               * EV'__ID_cls'
               * EKEY'with' * V'BlockI' * V'__Do'

    , Global  = KEY'global'
    , This    = KEY'this' * Cc(false)

    , Ext     = V'__ID_ext'
    , Var     = V'__ID_var'
    , Nat     = V'__ID_nat'

    , __ID_cls  = -KEYS * CK(m.R'AZ'*Alphanum^0)
    , __ID_ext  = -KEYS * CK(m.R'AZ'*ALPHANUM^0)
    , __ID_var  = (-KEYS * CK(m.R'az'*(Alphanum+'?')^0) + CK'_'*-Alphanum)
                    / function(id) return (string.gsub(id,'%?','_')) end
    , __ID_nat  = CK(  P'_' *Alphanum^1)
    , __ID_type = (CK(TYPES)+V'__ID_nat'+V'__ID_cls') *
                    (C'&' + C(P'*'^0)) *S /
                      function (id, star)
                        return (string.gsub(id..star,' ',''))
                      end

    , __ID_field = (CK(Alpha * (Alphanum+'?')^0) /
                    function (id)
                        return (string.gsub(id,'%?','_'))
                    end)

    , __tuple = Ct( (CKEY'hold'+Cc(false)) * EV'__ID_type' *
                      (EV'__ID_var'+Cc(false)) )
    , TupleType = K'(' * V'__tuple' * (EK','*V'__tuple')^0 * EK')'

    , STRING = CK( CK'"' * (P(1)-'"'-'\n')^0 * EK'"' )

    , Host    = KEY'native' * (#EKEY'do')*'do' * --m.S' \n\t'^0 *
                    ( C(V'_C') + C((P(1)-(m.S'\t\n\r '*'end'*P';'^0*'\n'))^0) )
                *S* EKEY'end'

    , RawStmt = K'{' * C((P(1)-'}')^0) * EK'}'
    , RawExp  = K'{' * C((P(1)-'}')^0) * EK'}'

    --, _C = '/******/' * (P(1)-'/******/')^0 * '/******/'
    , _C      = m.Cg(V'_CSEP','mark') *
                    (P(1)-V'_CEND')^0 *
                V'_CEND'
    , _CSEP = '/***' * (1-P'***/')^0 * '***/'
    , _CEND = m.Cmt(C(V'_CSEP') * m.Cb'mark',
                    function (s,i,a,b) return a == b end)

    , __SPACES = (  m.S'\t\n\r '
                + ('//' * (P(1)-'\n')^0 * P'\n'^-1)
                + ('#'  * (P(1)-'\n')^0 * P'\n'^-1) -- TODO: set of #'s/only after spaces
                + V'__comm'
                )^0

    , __comm    = '/' * m.Cg(P'*'^1,'comm') * (P(1)-V'__commcmp')^0 * V'__commcl'
                    / function () end
    , __commcl  = C(P'*'^1) * '/'
    , __commcmp = m.Cmt(V'__commcl' * m.Cb'comm',
                    function (s,i,a,b) return a == b end)
}

function err ()
    local x = (ERR_i<LST_i) and 'before' or 'after'
--DBG(LST_i, ERR_i, ERR_msg, _I2L[LST_i], I2TK[LST_i])
    local file, line = unpack(_LINES.i2l[LST_i])
    return 'ERR : '..file..
              ' : line '..line..
              ' : '..x..' `'..(I2TK[LST_i] or '?').."´"..
              ' : '..ERR_msg
end

if _RUNTESTS then
    assert(m.P(_GG):match(_OPTS.source), err())
else
    if not m.P(_GG):match(_OPTS.source) then     -- TODO: match only in ast.lua?
        DBG(err())
        os.exit(1)
    end
end
