script.Parent.BodyPosition.Position = script.Parent.Parent["Core Part"].Position
while true do
	wait(math.random(1,6))
	script.Parent.BodyAngularVelocity.AngularVelocity = Vector3.new(math.random(-2,2),math.random(-2,2),math.random(-2,2))
end