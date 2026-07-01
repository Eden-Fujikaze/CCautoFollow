local detector = peripheral.find("playerDetector")
local TARGET_NAME = "EdenFujikaze"
local RANGE = 50
local MIN_RANGE = 6 
local TURN_DEADZONE = 5 
local MOVE_EPS = 0.3

if not detector then error("no detector") end

local lastX, lastZ, heading = nil, nil, 0 -- heading in degrees, atan2(dz,dx)

local function normAngle(a)
  a = a % 360
  if a > 180 then a = a - 360 end
  return a
end

while true do
  local myX, myY, myZ = gps.locate()
  if not myX then
    print("GPS fix failed, skipping this cycle")
  else
    -- update heading estimate from actual displacement
    if lastX then
      local mdx, mdz = myX - lastX, myZ - lastZ
      if math.sqrt(mdx*mdx + mdz*mdz) > MOVE_EPS then
        heading = math.deg(math.atan2(mdz, mdx))
      end
    end
    lastX, lastZ = myX, myZ

    local ok, playerPos = pcall(function() return detector.getPlayerPos(TARGET_NAME) end)
    if not ok or not playerPos then
      print("Could not get player position:", playerPos)
      redstone.setAnalogOutput("left", 0)
      redstone.setAnalogOutput("right", 0)
      redstone.setOutput("front", false)
    else
      local dx = playerPos.x - myX
      local dz = playerPos.z - myZ
      local distance = math.sqrt(dx*dx + dz*dz)
      print(string.format("dist=%.1f heading=%.1f", distance, heading))

      if distance > RANGE or distance < MIN_RANGE then
        -- too far or too close: coast, no drive
        redstone.setOutput("front", false)
        redstone.setAnalogOutput("left", 0)
        redstone.setAnalogOutput("right", 0)
      else
        redstone.setOutput("front", true)

        local targetAngle = math.deg(math.atan2(dz, dx))
        local angleDiff = normAngle(targetAngle - heading) -- negative = turn left, positive = turn right

        if math.abs(angleDiff) < TURN_DEADZONE then
          redstone.setAnalogOutput("left", 0)
          redstone.setAnalogOutput("right", 0)
        else
          -- proportional steering: scale angle error (capped at 90°) to 1-15
          local strength = math.min(15, math.max(1, math.floor((math.abs(angleDiff) / 90) * 15)))
          if angleDiff > 0 then
            redstone.setAnalogOutput("right", strength)
            redstone.setAnalogOutput("left", 0)
          else
            redstone.setAnalogOutput("left", strength)
            redstone.setAnalogOutput("right", 0)
          end
        end
      end
    end
  end
  sleep(0.25)
end
