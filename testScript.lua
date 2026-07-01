local detector = peripheral.find("player_detector")
local TARGET_NAME = "Eden_Fujikaze"
local RANGE = 50
local MIN_RANGE = 6
local TURN_DEADZONE = 5
local MOVE_EPS = 0.3

local left = "bottom"
local right = "top"
local brake = "left"
local reverse = "right"

-- forward/reverse mode hysteresis: switch to reverse once target is behind
-- REVERSE_ENTER, switch back to forward once target is ahead of FORWARD_ENTER
local REVERSE_ENTER = 100  -- |angleDiff| beyond this -> go to reverse mode
local FORWARD_ENTER = 80   -- |angleDiff| below this -> go to forward mode

if not detector then error("no detector") end

local lastX, lastZ, heading = nil, nil, 0 -- heading in degrees, atan2(dz,dx)
local drivingReverse = false

local function normAngle(a)
  a = a % 360
  if a > 180 then a = a - 360 end
  return a
end

local function setBrake(on)
  redstone.setAnalogOutput(brake, on and 15 or 0)
end

local function setReverse(on)
  redstone.setAnalogOutput(reverse, on and 15 or 0)
end

local function setSteer(strength, dir)
  -- dir > 0 = turn right, dir < 0 = turn left, dir == 0 = straight
  if dir > 0 then
    redstone.setAnalogOutput(right, strength)
    redstone.setAnalogOutput(left, 0)
  elseif dir < 0 then
    redstone.setAnalogOutput(left, strength)
    redstone.setAnalogOutput(right, 0)
  else
    redstone.setAnalogOutput(left, 0)
    redstone.setAnalogOutput(right, 0)
  end
end

local function stopAndBrake()
  redstone.setOutput("front", false)
  setSteer(0, 0)
  setBrake(true)
end

while true do
  local myX, myY, myZ = gps.locate()

  if not myX then
    print("GPS fix failed, skipping this cycle")
  else
    if lastX then
      local mdx, mdz = myX - lastX, myZ - lastZ
      if math.sqrt(mdx * mdx + mdz * mdz) > MOVE_EPS then
        heading = math.deg(math.atan2(mdz, mdx))
      end
    end
    lastX, lastZ = myX, myZ

    local ok, playerPos = pcall(function() return detector.getPlayerPos(TARGET_NAME) end)

    if not ok or not playerPos then
      print("Could not get player position:", playerPos)
      stopAndBrake()
    else
      local dx = playerPos.x - myX
      local dz = playerPos.z - myZ
      local distance = math.sqrt(dx * dx + dz * dz)

      if distance > RANGE or distance < MIN_RANGE then
        stopAndBrake()
      else
        setBrake(false)

        local targetAngle = math.deg(math.atan2(dz, dx))
        -- raw bearing error relative to current forward heading
        local fwdDiff = normAngle(targetAngle - heading)

        -- hysteresis: decide whether we should be driving forward or reverse
        if drivingReverse then
          if math.abs(fwdDiff) < FORWARD_ENTER then
            drivingReverse = false
          end
        else
          if math.abs(fwdDiff) > REVERSE_ENTER then
            drivingReverse = true
          end
        end

        setReverse(drivingReverse)

        -- effective bearing error to steer against depends on drive direction:
        -- forward: steer toward targetAngle directly
        -- reverse: the vehicle's effective "front" is heading+180, so steer
        -- against the angle relative to that
        local angleDiff
        if drivingReverse then
          angleDiff = normAngle(targetAngle - (heading + 180))
        else
          angleDiff = fwdDiff
        end

        print(string.format("dist=%.1f heading=%.1f rev=%s diff=%.1f",
          distance, heading, tostring(drivingReverse), angleDiff))

        redstone.setOutput("front", true)

        if math.abs(angleDiff) < TURN_DEADZONE then
          setSteer(0, 0)
        else
          local strength = math.min(15, math.max(1, math.floor((math.abs(angleDiff) / 90) * 15)))
          setSteer(strength, angleDiff > 0 and 1 or -1)
        end
      end
    end
  end

  sleep(0.25)
end
