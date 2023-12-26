local modem = peripheral.find("modem",function(_,modem)
	return modem.isWireless()
end)

local speaker = peripheral.find("speaker") -- used for timing packets

assert(modem,"Missing wireless modem.")
assert(speaker,"Missing speaker.")

local aukit = require("aukit")

local protocol = "PASC"
local hostname = "radio"

local dataport = 8505
local discoveryport = 759

local modemname = peripheral.getName(modem)
local speakername = peripheral.getName(speaker)

local function tell(user,text)
	chatbox.tell(user,text,hostname)
end

----

local queue = {["requests"] = {},["playing"] = {}}

local function fetch(user,url,decoder)
	if queue.requests[user] or queue.playing[user] then
		tell(user,"You've already submitted a song.")
		return
	end
	
	url = url or ""
	
	http.request(url,nil,nil,true,"GET",true,10)
	
	queue.requests[user] =
	{
		["user"] = user,
		["url"] = url,
		["decoder"] = decoder,
		["data"] = nil,
		["stream"] = nil
	}
end

----

local events = {}

local songtimer

function events.command(user,command,args)
	if command == hostname then
		if args[1] == "help" or not args[1] then
			tell(user,[[
			CCSMB-5 compliant radio station on port 8505
			help - Shows command usage.
			queue - Shows every song in the queue.
			pcm <url> - Adds an 8-bit 48kHz PCM file to the queue.
			dfpwm <url> - Adds a DFPWM file to the queue.
			]])
		elseif args[1] == "queue" then
			local list
			
			if #queue.playing == 0 then
				list = "No songs currently queued."
			else
				list = "Currently queued:\n"
				
				for i,v in ipairs(queue.playing) do
					list = list .. string.format("%i - %s %s\n",i,v.user,v.url)
				end
			end
			
			tell(user,list)
		elseif args[1] == "pcm" then
			fetch(user,args[2],aukit.pcm)
		elseif args[1] == "dfpwm" then
			fetch(user,args[2],aukit.dfpwm)
		end
	end
end

function events.http_failure(url,reason)
	for user,request in pairs(queue.requests) do
		if request.url == url then
			tell(user,"HTTP Failed: " .. reason)
			queue.requests[user] = nil
			return
		end
	end
end

function events.http_success(url,response)
	for user,request in pairs(queue.requests) do
		if request.url == url then
			queue.requests[user] = nil
			
			local data = response.readAll()
			
			if #data > 2000 * 1024 then
				tell(user,"File must be under 2 megabytes in size.")
				return
			elseif #data / 48e+3 > 300 then
				tell(user,"Song must be less than 5 minutes long.")
				return
			end
			
			tell(user,"Success!")
			
			request.data = data
			
			queue.playing[user] = request
			table.insert(queue.playing,request)
			
			if not songtimer then
				songtimer = os.startTimer(0) -- start playing
			end
			
			return
		end
	end
end

function events.modem_message(side,port,_,data)
	if side == modemname and port == discoveryport then
		if type(data) == "table" and data.protocol == protocol and data.type == "discovery" then
			modem.transmit(discoveryport,discoveryport,
			{
				["channel"] = dataport,
				["station"] = hostname,
				["metadata"] = {["owner"] = "THKY"},
				["protocol"] = protocol
			})
		end
	end
end

function events.timer(timerid)
	if timerid == songtimer then
		speaker.stop()
		
		local song = queue.playing[1]
		
		if song then
			tell(song.user,"Decoding...")
			
			local ok,result = pcall(song.decoder,song.data)
			
			if ok then
				songtimer = os.startTimer(result:len() + 1) -- time until next song
				song.stream = result:stream(118 * 1024) -- 2.5 second long chunks
				events.speaker_audio_empty(speakername)
			else
				tell(song.user,result)
			end
		else
			songtimer = nil
		end
	end
end

function events.speaker_audio_empty(name)
	if name == speakername then
		local song = queue.playing[1]
		
		if song then
			local chunk = song.stream()
			
			if chunk then
				-- the standard requires a chunk to be sent right
				-- after the previous one ends, which makes it very likely
				-- for the audio on the client to stutter or become distorted
				speaker.playAudio(chunk[1])
				modem.transmit(dataport,dataport,
				{
					["buffer"] = chunk[1],
					["id"] = os.getComputerID(),
					["station"] = hostname,
					["metadata"] = {},
					["protocol"] = protocol
				})
			else
				table.remove(queue.playing,1)
				queue.playing[song.user] = nil
			end
		end
	end
end

----

modem.open(discoveryport)

while true do
	local event = {os.pullEventRaw()}
	
	if event[1] == "terminate" then
		modem.close(discoveryport)
		return
	end
	
	for type,callback in pairs(events) do
		if type == event[1] then
			table.remove(event,1)
			xpcall(callback,printError,table.unpack(event))
		end
	end
end
