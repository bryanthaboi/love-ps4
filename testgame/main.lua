-- Prueba minima de LOVE en PS4. Ejercita exactamente lo que gen1recomp necesita.
local lines, shader, canvas, t = {}, nil, nil, 0

local function say(fmt, ...)
    local s = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    lines[#lines+1] = s
    print("[testgame] " .. s)   -- va a stdout -> klog
end

function love.load()
    say("love._version = %s", love._version or "?")
    say("love._os      = %s", love._os or "?")
    say("_VERSION      = %s", _VERSION)
    say("jit           = %s", jit and jit.version or "ausente (Lua plano)")

    local w, h = love.graphics.getDimensions()
    say("ventana       = %dx%d", w, h)
    say("renderer      = %s", (select(1, love.graphics.getRendererInfo())))
    local name, ver, vendor, dev = love.graphics.getRendererInfo()
    say("GL            = %s / %s", tostring(ver), tostring(dev))

    -- Shader compilado en runtime: el corazon del asunto.
    local ok, sh = pcall(love.graphics.newShader, [[
        extern number tick;
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            float b = 0.5 + 0.5 * sin(tick + tc.x * 6.0);
            return vec4(color.r * b, color.g * (1.0 - b), color.b, 1.0);
        }
    ]])
    shader = ok and sh or nil
    say("newShader     = %s", ok and "OK" or ("FALLO: " .. tostring(sh)))

    -- Canvas: gen1recomp renderiza a 160x144 y escala.
    local ok2, cv = pcall(love.graphics.newCanvas, 160, 144)
    canvas = ok2 and cv or nil
    say("newCanvas     = %s", ok2 and "OK 160x144" or "FALLO")

    -- Filesystem escribible: donde iria el cache de la ROM.
    local okw = love.filesystem.write("prueba.txt", "hola desde la ps4")
    say("save dir      = %s", love.filesystem.getSaveDirectory())
    say("write         = %s", okw and "OK" or "FALLO")

    -- Audio: debe existir y ser inocuo (backend null).
    say("love.audio    = %s", love.audio and "presente" or "nil")
    if love.audio then
        local oka = pcall(love.audio.getVolume)
        say("audio.getVolume = %s", oka and "OK" or "error")
    end

    say("joysticks     = %d", love.joystick.getJoystickCount())
    local js = love.joystick.getJoysticks()[1]
    if js then say("  pad         = %s (%d ejes, %d botones)", js:getName(), js:getAxisCount(), js:getButtonCount()) end
end

function love.update(dt) t = t + dt end

function love.draw()
    love.graphics.clear(0.06, 0.08, 0.16)

    if canvas then
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0.1, 0.2, 0.35)
        love.graphics.setColor(1, 0.8, 0.2)
        love.graphics.rectangle("fill", 20, 20, 120, 104)
        love.graphics.setCanvas()
        love.graphics.setColor(1, 1, 1)
        if shader then love.graphics.setShader(shader); shader:send("tick", t) end
        love.graphics.draw(canvas, 1180, 120, 0, 4, 4)
        love.graphics.setShader()
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("LOVE " .. (love._version or "?") .. " en PlayStation 4", 60, 50)
    for i, l in ipairs(lines) do
        love.graphics.print(l, 60, 90 + i * 22)
    end
    love.graphics.print(string.format("fps %d   t %.1fs", love.timer.getFPS(), t), 60, 980)
end

function love.gamepadpressed(js, b)
    if b == "start" then love.event.quit() end
end
