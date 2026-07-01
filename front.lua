local detector = peripheral.find("player_detector")
local modem = peripheral.find("modem")
local TARGET_NAME = "Eden_Fujikaze"

if not detector then error("no detector") end
if not modem then error("no modem found") end

rednet.open(peripheral.getName(modem))

local RANGE = 50
local MIN_RANGE = 6
local MIN_RANGE_RELEASE = 8
local TICK = 0.25

local FACE_LEFT_BOTH  = "top"
local FACE_RIGHT_BOTH = "bottom"
local FACE_FRONT      = "front"

local ENTER_TURN = 15
local EXIT_TURN  = 5

local tooClose = false
local state = "stop" -- "stop" | "turnLeft" | "turnRight" | "front"
local rearPos = nil

local function normAngle(a)
  a = a % 360
  if a > 180 then a = a - 360 end
  return a
end

local function clearAll()
  redstone.setOutput(FACE_LEFT_BOTH, false)
  redstone.setOutput(FACE_RIGHT_BOTH, false)
  redstone.setOutput(FACE_FRONT, false)
end

local function setState(newState)
  if newState == state then
    if state == "turnLeft" then redstone.setOutput(FACE_LEFT_BOTH, true)
    elseif state == "turnRight" then redstone.setOutput(FACE_RIGHT_BOTH, true)
    elseif state == "front" then redstone.setOutput(FACE_FRONT, true)
    else clearAll()
    end
    return
  end
  state = newState
  clearAll()
  if state == "turnLeft" then redstone.setOutput(FACE_LEFT_BOTH, true)
  elseif state == "turnRight" then redstone.setOutput(FACE_RIGHT_BOTH, true)
  elseif state == "front" then redstone.setOutput(FACE_FRONT, true)
  end
end

local function pollRearPos()
  local id, msg, protocol = rednet.receive("car_rear_pos", 0)
  if msg then rearPos = msg end
end

clearAll()

while true do
  pollRearPos()

  local myX, myY, myZ = gps.locate()

  if not myX then
    print("GPS fix failed, stopping")
    setState("stop")
  elseif not rearPos then
    print("No rear position yet, stopping")
    setState("stop")
  else
    local hx, hz = myX - rearPos.x, myZ - rearPos.z
    local heading = normAngle(math.deg(math.atan2(hz, hx)))

    local ok, playerPos = pcall(function() return detector.getPlayerPos(TARGET_NAME) end)

    if not ok or not playerPos then
      print("Could not get player position:", playerPos)
      setState("stop")
    else
      local dx = playerPos.x - myX
      local dz = playerPos.z - myZ
      local distance = math.sqrt(dx * dx + dz * dz)

      if tooClose then
        if distance > MIN_RANGE_RELEASE then tooClose = false end
      else
        if distance < MIN_RANGE then tooClose = true end
      end

      if distance > RANGE or tooClose then
        setState("stop")
      else
        local targetAngle = math.deg(math.atan2(dz, dx))
        local diff = normAngle(targetAngle - heading)

        print(string.format("dist=%.1f heading=%.1f diff=%.1f state=%s",
          distance, heading, diff, state))

        if state == "front" then
          if math.abs(diff) > ENTER_TURN then
            setState(diff > 0 and "turnRight" or "turnLeft")
          else
            setState("front")
          end
        else
          if math.abs(diff) < EXIT_TURN then
            setState("front")
          else
            setState(diff > 0 and "turnRight" or "turnLeft")
          end
        end
      end
    end
  end

  sleep(TICK)
end
