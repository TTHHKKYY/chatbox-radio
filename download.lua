local dir = shell.dir()

local function promptget(url,path)
	if fs.exists(fs.combine(dir,path)) then
		print("Replace " .. path .. "? (Y/N)")
		
		while true do
			local _,key = os.pullEvent("key")
			
			if key == keys.y then
				break
			elseif key == keys.n then
				return
			end
		end
		
		fs.delete(path)
	end
	
	shell.run("wget",url,path)
end

promptget("https://raw.githubusercontent.com/TTHHKKYY/chatbox-radio/main/radio.lua","radio/server/server.lua")
promptget("https://raw.githubusercontent.com/TTHHKKYY/chatbox-radio/main/aukit.lua","radio/server/aukit.lua")
promptget("https://raw.githubusercontent.com/TTHHKKYY/chatbox-radio/main/radio-client.lua","radio/client.lua")
os.pullEvent()
