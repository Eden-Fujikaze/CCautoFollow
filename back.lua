local modem = peripheral.find("modem")
if not modem then error("no modem found") end

rednet.open(peripheral.getName(modem))

local CHANNEL_ID = 100 -- pick any id, front must match
local TICK = 0.25

while true do
  local x, y, z = gps.locate()
  if x then
    rednet.broadcast({x = x, y = y, z = z}, "car_rear_pos")
  end
  sleep(TICK)
end
