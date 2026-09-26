function love.conf(t)
    t.identity = "love-ps4-test"
    t.window.width, t.window.height = 1920, 1080
    t.window.resizable = false
    t.modules.physics = false
    t.modules.video = false
end
