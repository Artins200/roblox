stop = false
spawn(function()	
	wait(math.random(5,10))
	stop= true
end)

repeat 
	wait() 
	script.Parent.Rate=10+script.Parent.Parent.Velocity.Magnitude*2
until script.Parent.Parent.Velocity.Magnitude<=1 or stop == true
script.Parent.Rate=10
wait(math.random(3,10))
script.Parent.Enabled=false
wait(3)
script.Parent:remove()