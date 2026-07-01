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

-- pivot-turn tuning
local SHARP_TURN_THRESHOLD = 45   -- |angleDiff| above this triggers pivot-in-place turning
local PIVOT_BURST_TIME = 0.5      -- seconds spent in each forward/reverse burst while pivoting
local PIVOT_STEER_STRENGTH = 15   -- steering strength during pivot bursts

if not detector then error("no detector") end

local lastX, lastZ, heading = nil, nil, 0 -- heading in degrees, atan2(dz,dx)

-- pivot state machine
local pivoting = false
local pivotPhase = "forward" -- "forward" or "reverse"
local pivotTimer = 0
local pivotDir = 1 -- 1 = turn right (angleDiff > 0), -1 = turn left

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
  setReverse(false)
  setBrake(true)
  pivoting = false
end

while true do
  local dt = 0.25
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
      print(string.format("dist=%.1f heading=%.1f pivoting=%s", distance, heading, tostring(pivoting)))

      if distance > RANGE or distance < MIN_RANGE then
        -- too far or too close: brake, no drive
        stopAndBrake()
      else
        local targetAngle = math.deg(math.atan2(dz, dx))
        local angleDiff = normAngle(targetAngle - heading) -- negative = turn left, positive = turn right

        if math.abs(angleDiff) < TURN_DEADZONE then
          -- driving straight, close enough
          pivoting = false
          setBrake(false)
          setReverse(false)
          redstone.setOutput("front", true)
          setSteer(0, 0)

        elseif math.abs(angleDiff) >= SHARP_TURN_THRESHOLD then
          -- sharp angle: pivot in place via alternating forward/reverse bursts
          setBrake(false)

          if not pivoting then
            pivoting = true
            pivotPhase = "forward"
            pivotTimer = 0
            pivotDir = angleDiff > 0 and 1 or -1
          end

          -- re-evaluate turn direction each cycle in case target moved,
          -- but keep the burst phase/timer running
          pivotDir = angleDiff > 0 and 1 or -1

          pivotTimer = pivotTimer + dt
          if pivotTimer >= PIVOT_BURST_TIME then
            pivotTimer = 0
            pivotPhase = (pivotPhase == "forward") and "reverse" or "forward"
          end

          if pivotPhase == "forward" then
            setReverse(false)
            redstone.setOutput("front", true)
            setSteer(PIVOT_STEER_STRENGTH, pivotDir)
          else
            setReverse(true)
            redstone.setOutput("front", true)
            -- same physical steer direction: with drivetrain reversed,
            -- this walks the vehicle back on the opposite track, completing the pivot
            setSteer(PIVOT_STEER_STRENGTH, pivotDir)
          end

        else
          -- moderate angle: normal proportional steering, driving forward
          pivoting = false
          setBrake(false)
          setReverse(false)
          redstone.setOutput("front", true)

          local strength = math.min(15, math.max(1, math.floor((math.abs(angleDiff) / 90) * 15)))
          setSteer(strength, angleDiff > 0 and 1 or -1)
        end
      end
    end
  end

  sleep(0.25)
end
