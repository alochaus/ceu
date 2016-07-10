local awaits = {
    Par           = true,
    Every         = true,
    Async         = true,
    _Async_Thread = true,
    _Async_Isr    = true,
    Await_Ext     = true,
    Await_Wclock  = true,
    Await_Forever = true,
}

local function run (me, Loop)
    assert(AST.is_node(me))

    if awaits[me.tag] then
        return 'awaits'

    elseif me.tag=='Break' or me.tag=='Escape' then
        if Loop.__depth >= me.outer.__depth then
            return 'breaks'
else
DBG(Loop.__depth, me.outer.__depth)
error'TODO'
        end

    elseif me.tag=='If' or me.tag=='Par_Or' then
        local T do
            if me.tag == 'If' then
                local _,t,f = unpack(me)
                T = { t, f }
            else
                T = me
            end
        end
        local awaits = true
        for _,sub in ipairs(T) do
            local ret = run(sub, Loop)
            if ret == 'tight' then
                return 'tight'              -- "tight" if found at least one tight
            elseif ret == 'breaks' then
                awaits = false
            else
                assert(ret == 'awaits')
            end
        end
        if awaits then
            return 'awaits'                 -- "awaits" if all await
        else
            return 'breaks'                 -- "breaks" otherwise
        end

    elseif me.tag == 'Loop' then
        if me.tight == 'breaks' then
            return 'tight'
        else
            return 'awaits'
        end

    else
        for _, child in ipairs(me) do
            if AST.is_node(child) then
                local ret = run(child, Loop)
                if ret ~= 'tight' then
                    return ret
                end
            end
        end
        return 'tight'
    end
end

F = {
    Loop = function (me, ok)
        local max, body = unpack(me)

        if AST.par(me,'Async') or AST.par(me,'Async_Thread') or AST.par(me,'Async_Isr') then
            -- ok
        elseif max then
            -- ok
        elseif ok then
            -- ok
        else
            me.tight = run(body, me)
            WRN(me.tight~='tight', me, 'invalid tight `loop´ : unbounded number of non-awaiting iterations')
        end
    end,

    Loop_Num = function (me)
        local _, _, fr, _, to, _, body = unpack(me)
        F.Loop(me, (fr.is_const and to.is_const))
    end,
}

AST.visit(F)

