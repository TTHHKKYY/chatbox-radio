local modem = peripheral.find("modem",function(_,modem)
	return modem.isWireless()
end)

local speaker = peripheral.find("speaker")

assert(modem,"Missing modem.")
assert(speaker,"Missing speaker.")

local protocol = "PASC"

local discoveryport = 759

local modemname = peripheral.getName(modem)
local speakername = peripheral.getName(speaker)

----

local function validping(data)
	return type(data) == "table"
	and type(data.channel) == "number"
	and data.channel >= 0
	and data.channel <= 65535
	and type(data.station) == "string"
	and type(data.metadata) == "table"
	and data.protocol == protocol
end

local function validaudio(data)
	return type(data) == "table"
	and type(data.buffer) == "table"
	and type(data.id) == "number"
	and type(data.station) == "string"
	and type(data.metadata) == "table"
	and data.protocol == protocol
end

----

local hosts = {["byport"] = {},["byindex"] = {}}

local listindex = 1
local listscroll = 0

local currentstation

----

local function color(fg,bg)
	term.setTextColor(fg)
	term.setBackgroundColor(bg)
end

local pingtimer = os.startTimer(0)

modem.open(discoveryport)

while true do
	local width,height = term.getSize()
	
	local listlength = math.min(#hosts.byindex,height - 4)
	
	term.clear()
	
	term.setCursorPos(1,height - 1)
	term.write("Q: quit \24\25: scroll \27: listen")
	term.setCursorPos(1,height)
	term.write("F: fix sound R: refresh: D: disconnect")
	
	if currentstation then
		color(colors.blue,colors.black)
		term.setCursorPos(1,height - 2)
		term.write("Selected: " .. currentstation.station .. " on " .. currentstation.channel)
	end
	
	for i=1,listlength do
		local station = hosts.byindex[i + listscroll]
		
		if station then
			if i == listindex - listscroll then
				color(colors.black,colors.white)
			else
				color(colors.white,colors.black)
			end
			
			term.setCursorPos(1,i)
			term.write(station.station .. " " .. station.channel)
		end
	end
	
	color(colors.white,colors.black)
	
	----
	
	local event = {os.pullEventRaw()}
	
	if event[1] == "modem_message" then
		local side,port,data = event[2],event[3],event[5]
		
		if side == modemname and port == discoveryport and validping(data) then
			if not hosts.byport[data.station] then
				hosts.byport[data.station] = data
				table.insert(hosts.byindex,data)
			end
		elseif side == modemname and currentstation and port == currentstation.channel and validaudio(data) then
			speaker.playAudio(data.buffer)
		end
	elseif event[1] == "key" then
		local key = event[2]
		
		if key == keys.q then -- quit
			break
		elseif key == keys.r then -- refresh
			hosts.byport = {}
			hosts.byindex = {}
			
			listindex = 1
			listscroll = 0
			
			pingtimer = os.startTimer(0)
		end
		
		if key == keys.up or key == keys.numPad8 or key == keys.w then -- scroll up
			listindex = math.max(listindex - 1,1)
			
			if listindex <= listscroll then
				listscroll = math.max(scroll - 1,0)
			end
		elseif key == keys.down or key == keys.numPad2 or key == keys.s then -- scroll down
			listindex = math.min(listindex + 1,#hosts.byindex)
			
			if listindex > listscroll + listlength then
				listscroll = math.min(scroll + 1,#hosts.byindex)
			end
		end
		
		if key == keys.enter or key == keys.numPadEnter or key == keys.left then -- connect
			if currentstation then
				modem.close(currentstation.channel)
				speaker.stop()
			end
			
			currentstation = hosts.byindex[listindex]
			
			if currentstation then -- there could be no channel selected (hosts.byindex is empty)
				modem.open(currentstation.channel)
			end
		end
		
		if key == keys.f then -- quick fix for audio distortion
			speaker.stop()
		end
		
		if key == keys.d then -- disconnect
			if currentstation then
				modem.close(currentstation.channel)
				speaker.stop()
				currentstation = nil
			end
		end
	elseif event[1] == "timer" then
		local timerid = event[2]
		
		if timerid == pingtimer then
			modem.transmit(discoveryport,discoveryport,
			{
				["type"] = "discovery",
				["protocol"] = protocol
			})
			pingtimer = os.startTimer(5)
		end
	elseif event[1] == "terminate" then
		break
	end
end

if currentstation then
	modem.close(currentstation.channel)
	speaker.stop()
end

modem.close(discoveryport)
term.clear()
term.setCursorPos(1,1)

os.pullEvent()
