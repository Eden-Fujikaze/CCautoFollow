local detector = peripheral.find("player_detector")
local TARGET_NAME = "Eden_Fujikaze"

local RANGE = 50
local MIN_RANGE = 6          -- brake once closer than this
local MIN_RANGE_RELEASE = 8  -- must move back out past this before driving resumes
local TURN_DEADZONE = 5
local MOVE_EPS = 0.3

local left = "bottom"
local right = "top"
local brake = "left"
local reverse = "right"

-- forward/reverse mode hysteresis + cooldown
local REVERSE_ENTER = 100        -- |fwdDiff| beyond this -> switch to reverse mode
local FORWARD_ENTER = 80         -- |fwdDiff| below this -> switch to forward mode
local MODE_SWITCH_COOLDOWN = 2.0 -- min seconds between gear flips, prevents chatter
local TICK = 0.25

if not detector then error("no detector") end

local lastX, lastZ = nil, nil
local heading = 0            -- true facing, degrees, estimated from GPS deltas
local drivingReverse = false -- current commanded gear
local timeSinceSwitch = 999
local tooClose = false

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
    -- 1. Update heading estimate from GPS motion.
    -- Correct for the reverse offset using LAST tick's commanded gear (not this
    -- tick's), which is what makes this safe to compute unconditionally: heading
    -- never depends on any value derived from itself within the same tick.
    if lastX then
      local mdx, mdz = myX - lastX, myZ - lastZ
      if math.sqrt(mdx * mdx + mdz * mdz) > MOVE_EPS then
        local raw = math.deg(math.atan2(mdz, mdx))
        if drivingReverse then
          heading = normAngle(raw + 180)
        else
          heading = normAngle(raw)
        end
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

      -- 2. too-close hysteresis: avoids bang-bang braking right at MIN_RANGE
      if tooClose then
        if distance > MIN_RANGE_RELEASE then
          tooClose = false
        end
      else
        if distance < MIN_RANGE then
          tooClose = true
        end
      end

      if distance > RANGE or tooClose then
        stopAndBrake()
      else
        setBrake(false)

        local targetAngle = math.deg(math.atan2(dz, dx))
        local fwdDiff = normAngle(targetAngle - heading)

        -- 3. forward/reverse mode hysteresis, gated by cooldown to prevent chatter
        timeSinceSwitch = timeSinceSwitch + TICK
        if timeSinceSwitch >= MODE_SWITCH_COOLDOWN then
          if drivingReverse then
            if math.abs(fwdDiff) < FORWARD_ENTER then
              drivingReverse = false
              timeSinceSwitch = 0
            end
          else
            if math.abs(fwdDiff) > REVERSE_ENTER then
              drivingReverse = true
              timeSinceSwitch = 0
            end
          end
        end

        setReverse(drivingReverse)

        -- 4. steer relative to effective facing (heading, or heading+180 in reverse)
        local angleDiff
        if drivingReverse then
          angleDiff = normAngle(targetAngle - normAngle(heading + 180))
        else
          angleDiff = fwdDiff
        end

        print(string.format("dist=%.1f heading=%.1f rev=%s diff=%.1f",
          distance, heading, tostring(drivingReverse), angleDiff))

        redstone.setOutput("front", true)

        if math.abs(angleDiff) < TURN_DEADZONE then
          setSteer(0, 0)
        else
          -- full lock reached by 45 degrees off, floor of 6 so small errors still correct
          local norm = math.min(1, math.abs(angleDiff) / 45)
          local strength = math.min(15, math.max(6, math.floor(norm * 15)))
          setSteer(strength, angleDiff > 0 and 1 or -1)
        end
      end
    end
  end

  sleep(TICK)
end
