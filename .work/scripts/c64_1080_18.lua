local maxtime = 30
local Time = 0
function move(target, engine)
	local origincframe = engine:findFirstChild("BodyGyro").cframe
	local dir
	if target ~= nil then
	dir = (target.Position - engine.Position).unit
	else
	dir = engine.CFrame.lookVector 
	end
	local spawnPos = engine.Position
	local pos = spawnPos + dir

	temp = script.Parent.MySpeed.Value
	if(target ~= nil) then
		targetvel = target.Velocity
	dist = (target.Position - engine.Position).magnitude
	spd = temp - dist
	test = target.Position+(targetvel/Vector3.new(temp,temp,temp)*(dist))  -- +Vector3.new(0,-1,0)
		engine:findFirstChild("BodyGyro").maxTorque = Vector3.new(17900,17900, 17900)
		engine:findFirstChild("BodyGyro").cframe = CFrame.new(pos,  test+dir)
	else
		engine:findFirstChild("BodyGyro").maxTorque = Vector3.new(17900,17900, 17900)
		engine:findFirstChild("BodyGyro").cframe = CFrame.new(pos, pos+dir)
	end
end
function Vel(speed,lv)
	return lv*Vector3.new(speed,speed,speed)
end
function boomson(hit)
	if hit.Anchored == false then
		if math.random(1,5)==1 then
			local b=script.fire:Clone()
			b.Enabled=true
			b.Script.Disabled=false
			b.Parent=hit
			local b=script.smoke:Clone()
			b.Enabled=true
			b.Script.Disabled=false
			b.Parent=hit
			
		end
	end
end
script.Parent.a1.smoke.Enabled=true
script.Parent.sheoooeoews:Play()
local armed = false
script.Parent.a1.fire.Enabled=true
		base = script.Parent
		deBounce = false
		function kill(part)
			if armed == false then return end
			if(part == nil) then return end
			if(part.Parent == nil) then return end
			if(deBounce == false) then
				deBounce = true
				script.Parent.CanCollide = false
				exp = Instance.new("Explosion")
				exp.Parent = game.Workspace
				exp.Position = script.Parent.Position-Vector3.new(0,12,0) -- launch stuff upwards (looks cooler)
				exp.BlastRadius = 40
				exp.Visible=false
				exp.BlastPressure = 350000
				script.Parent.boeam:Play()
				script.Parent.a1.fire:Remove()
				script.Parent.sheoooeoews:Stop()
				script.Parent.dp:Emit(30)
				script.Parent.dsp:Emit(30)
				script.Parent.ds:Emit(1)
				script.Parent.MyTarget.Value:remove()
				exp.Hit:connect(boomson)
			end
			script.Parent.Anchored = true
			script.Parent.Transparency = 1
			wait(5)
			script.Parent:remove()
		end
		base.Touched:connect(kill)
		while Time < maxtime do
			Time = Time +0.1
			MyTarget = script.Parent.MyTarget.Value
			if Time >= 0.2 then
				armed=true
				
			end
			if Time >= 0.5 then
				script.Parent.a1.smoke.Enabled=false
			end
			if Time>= 0.6 then
					move(MyTarget,script.Parent)
					script.Parent.MySpeed.Value=500
					script.Parent.BodyGyro.P=1250
			else 
			     	move(nil,script.Parent)
			script.Parent.MySpeed.Value=400
			end
			if Time >= 2 then
				script.Parent.BodyGyro.D=250
			end
			if Time >= 5 then
				script.Parent.BodyGyro.D=50
			end
			script.Parent.BodyVelocity.velocity = Vel(script.Parent.MySpeed.Value,script.Parent.CFrame.lookVector)
			wait(0.1)
		end

		wait(10)
		script.Parent.BodyVelocity:Remove()
		script.Parent.BodyGyro:Remove()
	