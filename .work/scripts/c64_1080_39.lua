script.Parent.BodyPosition.Position = script.Parent.Parent["Core Part"].Position
while true do
	wait(math.random(1,3))
	script.Parent.BodyAngularVelocity.AngularVelocity = Vector3.new(math.random(-1,1),math.random(-1,1),math.random(-1,1))
end