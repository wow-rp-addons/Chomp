--[[
	© Justin Snelgrove

	Permission to use, copy, modify, and distribute this software for any
	purpose with or without fee is hereby granted, provided that the above
	copyright notice and this permission notice appear in all copies.

	THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
	WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
	MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
	SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
	WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
	OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
	CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

	--

	Portions of this file are copied directly from ChatThrottleLib (v23) by
	mikk, which was released into the public domain.
]]

if not __chomp_internal or not __chomp_internal.LOADING then
	return
end

local Internal = __chomp_internal

-- The following code provides a compatibility layer for addons using
-- ChatThrottleLib. It won't load (and Chomp will feed messages into CTL) if
-- there's a newer version of CTL loaded than this layer is compatible with, or
-- if a newer version is loaded after Chomp. This can cause some weird things
-- to happen if someone decides to LoadOnDemand a newer copy of ChatThrottleLib,
-- but that will hopefully be vanishingly rare.

local CTL_VERSION = 24

local PRIORITY_FROM_CTL = { BULK = "LOW", NORMAL = "MEDIUM", ALERT = "HIGH" }

if ChatThrottleLib and not ChatThrottleLib.isChomp and ChatThrottleLib.version > CTL_VERSION then
	Internal.ChatThrottleLib = true
	return
end

if type(ChatThrottleLib) ~= "table" then
	ChatThrottleLib = {}
else
	setmetatable(ChatThrottleLib, nil)
end
ChatThrottleLib.version = nil -- Handled in metatable.
ChatThrottleLib.isChomp = true

function ChatThrottleLib:SendAddonMessage(priorityName, prefix, text, kind, target, queueName, callback, callbackArg)
	if not priorityName or not prefix or not text or not kind or not PRIORITY_FROM_CTL[priorityName] then
		error("Usage: ChatThrottleLib:SendAddonMessage(\"{BULK||NORMAL||ALERT}\", \"prefix\", \"text\", \"chattype\"[, \"target\"])", 2)
	elseif callback and type(callback) ~= "function" then
		error("ChatThrottleLib:SendAddonMessage(): callback: expected function, got " .. type(callback), 2)
	elseif #text > 255 then
		error("ChatThrottleLib:SendAddonMessage(): message length cannot exceed 255 bytes", 2)
	end
	if kind == "CHANNEL" then
		target = tonumber(target)
	end
	AddOn_Chomp.SendAddonMessage(prefix, text, kind, target, PRIORITY_FROM_CTL[priorityName], queueName or ("%s%s%s"):format(prefix, kind, (tostring(target) or "")), callback, callbackArg)
end

function ChatThrottleLib:SendChatMessage(priorityName, prefix, text, kind, language, target, queueName, callback, callbackArg)
	if not priorityName or not prefix or not text or not PRIORITY_FROM_CTL[priorityName] then
		error("Usage: ChatThrottleLib:SendChatMessage(\"{BULK||NORMAL||ALERT}\", \"prefix\", \"text\"[, \"chattype\"[, \"language\"[, \"destination\"]]]", 2)
	elseif callback and type(callback) ~= "function" then
		error("ChatThrottleLib:SendChatMessage(): callback: expected function, got " .. type(callback), 2)
	elseif #text > 255 then
		error("ChatThrottleLib:SendChatMessage(): message length cannot exceed 255 bytes", 2)
	end
	if kind == "CHANNEL" then
		target = tonumber(target)
	end
	AddOn_Chomp.SendChatMessage(text, kind, language, target, PRIORITY_FROM_CTL[priorityName], queueName or ("%s%s%s"):format(prefix, (kind or "SAY"), (tostring(target) or "")), callback, callbackArg)
end

function ChatThrottleLib.Hook_SendAddonMessage()
end
ChatThrottleLib.Hook_SendChatMessage = ChatThrottleLib.Hook_SendAddonMessage

-- This metatable catches changes to the CTL version, in case of a newer
-- version of CTL replacing this compatibility layer.
setmetatable(ChatThrottleLib, {
	__index = function(self, key)
		if key == "version" then
			return CTL_VERSION
		elseif key == "securelyHooked" then
			return true
		end
	end,
	__newindex = function(self, key, value)
		if key == "version" then
			self.isChomp = nil
			Internal.ChatThrottleLib = true
			setmetatable(self, nil)
		end
		rawset(self, key, value)
	end,
})

Internal.ChatThrottleLib = nil
