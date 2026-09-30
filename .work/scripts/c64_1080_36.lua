script.Parent.BodyPosition.Position = script.Parent.Position
while true do
	wait(math.random(1,3))
	script.Parent.BodyAngularVelocity.AngularVelocity = Vector3.new(math.random(-6,6),math.random(-6,6),math.random(-6,6))
end