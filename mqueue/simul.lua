function DBG (...)
    local t = {}
    for i=1, select('#',...) do
        t[#t+1] = tostring( select(i,...) )
    end
    if #t == 0 then
        t = { [1]=debug.traceback() }
    end
    io.stderr:write(table.concat(t,'\t')..'\n')
end

module((...), package.seeall)

QU = {
    LINK  = -1,
    TIME  = -10,
    ASYNC = -11,
}

local H = [[
C do
    /******/
    #include <stdarg.h>

    void MQ (int id, int v) {
        char buf[10];
        int len = 0;
        memcpy(buf, &id, sizeof(s16));
            len += sizeof(s16);
        memcpy(buf+len, &v, sizeof(int));
            len += sizeof(int);
        mq_send(ceu_mqueue_mqd, buf, len, 0);
    }

    void DBG (char *fmt, ... )
    {
        char tmp[128];
        va_list args;
        va_start(args, fmt);
        vsnprintf(tmp, 128, fmt, args);
        va_end(args);
        printf("[ %s ] %s", CEU_DBG, tmp);
    }
    /******/
end
]]

local _names = {}

function app (app)
    assert(app.name,   'missing `name´')
    assert(app.source, 'missing `source´')

    app._name = string.gsub(app.name, '%s', '_')
    assert(not _names[app._name], 'duplicate `name´')
    _names[app._name] = true

    app._exe   = app._name .. '.exe'
    app._ceu   = '_'..app._name..'.ceu'
    app._queue = app._queue or '/'..app._name

    app.start = _start
    app.kill  = _kill

    local DEFS = [[
C do /******/
    #define CEU_DBG "]]..app._name..[["
]]
    for k, v in pairs(app.defines or {}) do
        DEFS = DEFS .. '#define '..k..' '..v..'\n'
    end
    DEFS = DEFS .. '/******/ end\n'

    app.source = '/*{-{*/' .. DEFS
                     .. H
              .. '/*}-}*/' .. app.source

    f = assert(io.open(app._ceu, 'w'))
    f:write(app.source)
    f:close()
    DBG('===> Compiling '..app._ceu..'...')
    assert(os.execute('./ceu '..app._ceu
                        .. ' --m4'
                        .. ' --output _ceu_code.c'
                        .. ' --events-file _ceu_events.h'
                     ) == 0)
    assert(os.execute('gcc -o '..app._exe..' main.c -lrt')==0)

    DBG('', 'queue:', app._queue)

    app.io = {}
    local str = assert(io.open('_ceu_events.h')):read'*a'
    DBG('', 'inputs:')
    for evt, v in string.gmatch(str,'(IN_%u[^%s]*)%s+(%d+)\n') do
        app.io[evt] = v
        DBG('','',evt, v)
    end
    DBG('', 'outputs:')
    for evt, v in string.gmatch(str,'(OUT_%u[^%s]*)%s+(%d+)\n') do
        app.io[evt] = v
        DBG('','',evt, v)
    end

    assert(os.execute('./qu.exe create '..app._queue) == 0)

    return app
end

function link (app1,out, app2,inp)
    DBG('===> Linking '..app1._queue..'/'..out..' -> '..app2._queue..'/'..inp)
    os.execute('./qu.exe send '..app1._queue..' '..QU.LINK..' '..app1.io[out]
                          ..' '..app2._queue..' '..app2.io[inp])
end

function emit (app, inp, v)
    DBG('===> Emit '..app._queue..'/'..inp..'('..v..')')
    if inp > 0 then
        os.execute('./qu.exe send '..app._queue..' '..app.io[inp]..' '..v)
    else
        os.execute('./qu.exe send '..app._queue..' '..inp..' '..v)
    end
end

function _start (app)
    DBG('===> Executing '..app.name..'...')
    os.execute('./'..app._exe..' '..app._queue..'&')
end

function _kill (app)
    os.remove('/dev/mqueue/'..app._queue)
    os.remove(app._ceu)
    os.execute('killall '..app._exe)
end
